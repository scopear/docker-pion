package main

import (
	"flag"
	"fmt"
	"log"
	"net"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/pion/logging"
	"github.com/pion/turn/v2"
)

func main() {

	// User environment variables
	turn_external_ip4 := "127.0.0.1"
	if len(os.Getenv("TURN_EXTERNAL_IPV4")) != 0 {
		turn_external_ip4 = os.Getenv("TURN_EXTERNAL_IPV4")
	}
	turn_server_port := 3478
	if len(os.Getenv("TURN_SERVER_PORT")) != 0 {
		value, err := strconv.Atoi(os.Getenv("TURN_SERVER_PORT"))
		if err != nil {
			log.Fatal(err)
		}
		turn_server_port = value
	}
	turn_user_name := "scopear"
	if len(os.Getenv("TURN_USER_NAME")) != 0 {
		turn_user_name = os.Getenv("TURN_USER_NAME")
	}
	turn_user_password := "changeme"
	if len(os.Getenv("TURN_USER_PASSWORD")) != 0 {
		turn_user_password = os.Getenv("TURN_USER_PASSWORD")
	}
	turn_server_realm := "ScopeAR"
	if len(os.Getenv("TURN_REALM_NAME")) != 0 {
		turn_server_realm = os.Getenv("TURN_REALM_NAME")
	}
	turn_client_ping_enabled := false
	if len(os.Getenv("TURN_CLIENT_PING_ENABLED")) != 0 {
		value, err := strconv.ParseBool(os.Getenv("TURN_CLIENT_PING_ENABLED"))
		if err != nil {
			log.Fatal(err)
		}
		turn_client_ping_enabled = value
	}

	// Overriding flags
	host := flag.String("host", turn_external_ip4, "TURN Server name.")
	port := flag.Int("port", turn_server_port, "Listening port.")
	user := flag.String("user", turn_user_name+"="+turn_user_password, "A pair of username and password (e.g. \"user=pass\")")
	realm := flag.String("realm", turn_server_realm, "Realm (defaults to \"ScopeAR\")")
	ping := flag.Bool("ping", turn_client_ping_enabled, "Run ping test")
	flag.Parse()

	// WARNINGS
	if *host == "127.0.0.1" {
		fmt.Printf("[WARNING] TURN_EXTERNAL_IPV4 is set to the default of `127.0.0.1` !!!")
	}
	if *user == "scopear=changeme" {
		fmt.Printf("[WARNING] Using default TURN user and password !!!")
	}

	// Start turn client
	turnClient(host, port, realm, user, ping)
}

func turnClient(host *string, port *int, realm *string, user *string, ping *bool) {
	cred := strings.SplitN(*user, "=", 2)

	// TURN client won't create a local listening socket by itself.
	conn, err := net.ListenPacket("udp4", "0.0.0.0:0")
	if err != nil {
		panic(err)
	}
	defer func() {
		if closeErr := conn.Close(); closeErr != nil {
			panic(closeErr)
		}
	}()

	turnServerAddr := fmt.Sprintf("%s:%d", *host, *port)

	cfg := &turn.ClientConfig{
		STUNServerAddr: turnServerAddr,
		TURNServerAddr: turnServerAddr,
		Conn:           conn,
		Username:       cred[0],
		Password:       cred[1],
		Realm:          *realm,
		LoggerFactory:  logging.NewDefaultLoggerFactory(),
	}

	client, err := turn.NewClient(cfg)
	if err != nil {
		panic(err)
	}
	defer client.Close()

	// Start listening on the conn provided.
	err = client.Listen()
	if err != nil {
		panic(err)
	}

	// Allocate a relay socket on the TURN server. On success, it
	// will return a net.PacketConn which represents the remote
	// socket.
	relayConn, err := client.Allocate()
	if err != nil {
		panic(err)
	}
	defer func() {
		if closeErr := relayConn.Close(); closeErr != nil {
			panic(closeErr)
		}
	}()

	// The relayConn's local address is actually the transport
	// address assigned on the TURN server.
	log.Printf("relayed-address=%s", relayConn.LocalAddr().String())

	// If you provided `-ping`, perform a ping test agaist the
	// relayConn we have just allocated.
	if *ping {
		err = doPingTest(client, relayConn)
		if err != nil {
			panic(err)
		}
	}
}

func doPingTest(client *turn.Client, relayConn net.PacketConn) error {
	// Send BindingRequest to learn our external IP
	mappedAddr, err := client.SendBindingRequest()
	if err != nil {
		return err
	}

	// Set up pinger socket (pingerConn)
	pingerConn, err := net.ListenPacket("udp4", "0.0.0.0:0")
	if err != nil {
		panic(err)
	}
	defer func() {
		if closeErr := pingerConn.Close(); closeErr != nil {
			panic(closeErr)
		}
	}()

	// Punch a UDP hole for the relayConn by sending a data to the mappedAddr.
	// This will trigger a TURN client to generate a permission request to the
	// TURN server. After this, packets from the IP address will be accepted by
	// the TURN server.
	_, err = relayConn.WriteTo([]byte("Hello"), mappedAddr)
	if err != nil {
		return err
	}

	// Start read-loop on pingerConn
	go func() {
		buf := make([]byte, 1600)
		for {
			n, from, pingerErr := pingerConn.ReadFrom(buf)
			if pingerErr != nil {
				break
			}

			msg := string(buf[:n])
			if sentAt, pingerErr := time.Parse(time.RFC3339Nano, msg); pingerErr == nil {
				rtt := time.Since(sentAt)
				log.Printf("%d bytes from from %s time=%d ms\n", n, from.String(), int(rtt.Seconds()*1000))
			}
		}
	}()

	// Start read-loop on relayConn
	go func() {
		buf := make([]byte, 1600)
		for {
			n, from, readerErr := relayConn.ReadFrom(buf)
			if readerErr != nil {
				break
			}

			// Echo back
			if _, readerErr = relayConn.WriteTo(buf[:n], from); readerErr != nil {
				break
			}
		}
	}()

	time.Sleep(500 * time.Millisecond)

	// Send 10 packets from relayConn to the echo server
	for i := 0; i < 10; i++ {
		msg := time.Now().Format(time.RFC3339Nano)
		_, err = pingerConn.WriteTo([]byte(msg), relayConn.LocalAddr())
		if err != nil {
			return err
		}

		// For simplicity, this example does not wait for the pong (reply).
		// Instead, sleep 1 second.
		time.Sleep(time.Second)
	}

	return nil
}
