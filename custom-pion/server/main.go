/*
This is based on Pion examples
*/

package main

import (
	"flag"
	"fmt"
	"log"
	"net"
	"os"
	"os/signal"
	"regexp"
	"strconv"
	"syscall"

	"github.com/pion/logging"
	"github.com/pion/stun"
	"github.com/pion/turn/v2"
)

// stunLogger wraps a PacketConn and prints incoming/outgoing STUN packets
// This pattern could be used to capture/inspect/modify data as well
type stunLogger struct {
	net.PacketConn
}

func (s *stunLogger) WriteTo(p []byte, addr net.Addr) (n int, err error) {
	if n, err = s.PacketConn.WriteTo(p, addr); err == nil && stun.IsMessage(p) {
		msg := &stun.Message{Raw: p}
		if err = msg.Decode(); err != nil {
			return
		}

		fmt.Printf("Outbound STUN: %s \n", msg.String())
	}

	return
}

func (s *stunLogger) ReadFrom(p []byte) (n int, addr net.Addr, err error) {
	if n, addr, err = s.PacketConn.ReadFrom(p); err == nil && stun.IsMessage(p) {
		msg := &stun.Message{Raw: p}
		if err = msg.Decode(); err != nil {
			return
		}

		fmt.Printf("Inbound STUN: %s \n", msg.String())
	}

	return
}

func turnServer(publicIP *string, port *int, realm *string, users *string, minPort *int, maxPort *int) {

	// Print configuration info
	fmt.Printf("=== Start TURN Config ===\n")
	fmt.Printf("TURN_EXTERNAL_IPV4=" + *publicIP + "\n")
	fmt.Printf("TURN_SERVER_PORT=%v\n", *port)
	fmt.Printf("TURN_REALM_NAME=" + *realm + "\n")
	fmt.Printf("TURN_RELAY_PORT_RANGE_MIN=%v\n", *minPort)
	fmt.Printf("TURN_RELAY_PORT_RANGE_MAX=%v\n", *maxPort)
	fmt.Printf("=== End TURN Config ===" + "\n")

	// Create a UDP listener to pass into pion/turn
	// pion/turn itself doesn't allocate any UDP sockets, but lets the user pass them in
	// this allows us to add logging, storage or modify inbound/outbound traffic
	udpListener, err := net.ListenPacket("udp4", "0.0.0.0:"+strconv.Itoa(*port))
	if err != nil {
		log.Panicf("Failed to create TURN server listener: %s", err)
	}

	// Create a TCP listener to pass into pion/turn
	// pion/turn itself doesn't allocate any TCP listeners, but lets the user pass them in
	// this allows us to add logging, storage or modify inbound/outbound traffic
	tcpListener, err := net.Listen("tcp4", "0.0.0.0:"+strconv.Itoa(*port))
	if err != nil {
		log.Panicf("Failed to create TURN server listener: %s", err)
	}

	// // LoggerFactory must be set for logging from this server.
	// loggerFactory, err := logging.
	// if err != nil {
	// 	log.Panicf("Failed to create loggerFactory")
	// }

	// Cache -users flag for easy lookup later
	// If passwords are stored they should be saved to your DB hashed using turn.GenerateAuthKey
	usersMap := map[string][]byte{}
	for _, kv := range regexp.MustCompile(`(\w+)=(\w+)`).FindAllStringSubmatch(*users, -1) {
		usersMap[kv[1]] = turn.GenerateAuthKey(kv[1], *realm, kv[2])
	}

	s, err := turn.NewServer(turn.ServerConfig{
		Realm: *realm,
		// Set AuthHandler callback
		// This is called everytime a user tries to authenticate with the TURN server
		// Return the key for that user, or false when no user is found
		AuthHandler: func(username string, realm string, srcAddr net.Addr) ([]byte, bool) {
			if key, ok := usersMap[username]; ok {
				return key, true
			}
			return nil, false
		},
		// PacketConnConfigs is a list of UDP Listeners and the configuration around them
		PacketConnConfigs: []turn.PacketConnConfig{
			{
				PacketConn: &stunLogger{udpListener}, // Enabled logging output
				RelayAddressGenerator: &turn.RelayAddressGeneratorPortRange{
					RelayAddress: net.ParseIP(*publicIP), // Claim that we are listening on IP passed by user (This should be your Public IP)
					Address:      "0.0.0.0",              // But actually be listening on every interface
					MinPort:      uint16(*minPort),
					MaxPort:      uint16(*maxPort),
				},
			},
		},
		// ListenerConfig is a list of Listeners and the configuration around them
		ListenerConfigs: []turn.ListenerConfig{
			{
				Listener: tcpListener,
				RelayAddressGenerator: &turn.RelayAddressGeneratorPortRange{
					RelayAddress: net.ParseIP(*publicIP),
					Address:      "0.0.0.0",
					MinPort:      uint16(*minPort),
					MaxPort:      uint16(*maxPort),
				},
			},
		},
		LoggerFactory: logging.NewDefaultLoggerFactory(),
	})
	if err != nil {
		log.Panic(err)
	}

	// Block until user sends SIGINT or SIGTERM
	sigs := make(chan os.Signal, 1)
	signal.Notify(sigs, syscall.SIGINT, syscall.SIGTERM)
	<-sigs

	if err = s.Close(); err != nil {
		log.Panic(err)
	}
}

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
	turn_server_realm := "ScopeAR"
	if len(os.Getenv("TURN_REALM_NAME")) != 0 {
		turn_server_realm = os.Getenv("TURN_REALM_NAME")
	}
	turn_user_name := "scopear"
	if len(os.Getenv("TURN_USER_NAME")) != 0 {
		turn_user_name = os.Getenv("TURN_USER_NAME")
	}
	turn_user_password := "changeme"
	if len(os.Getenv("TURN_USER_PASSWORD")) != 0 {
		turn_user_password = os.Getenv("TURN_USER_PASSWORD")
	}
	turn_relay_port_range_min := 49152
	if len(os.Getenv("TURN_RELAY_PORT_RANGE_MIN")) != 0 {
		value, err := strconv.Atoi(os.Getenv("TURN_RELAY_PORT_RANGE_MIN"))
		if err != nil {
			log.Fatal(err)
		}
		turn_relay_port_range_min = value
	}
	turn_relay_port_range_max := 65535
	if len(os.Getenv("TURN_RELAY_PORT_RANGE_MAX")) != 0 {
		value, err := strconv.Atoi(os.Getenv("TURN_RELAY_PORT_RANGE_MAX"))
		if err != nil {
			log.Fatal(err)
		}
		turn_relay_port_range_max = value
	}

	// Overriding flags
	publicIP := flag.String("public-ip", turn_external_ip4, "IP Address that TURN can be contacted by.")
	port := flag.Int("port", turn_server_port, "Listening port.")
	//TODO: we don't deal with multiple users in our ENV or client healthcheck
	users := flag.String("users", turn_user_name+"="+turn_user_password, "List of username and password (e.g. \"user=pass,user=pass\")")
	realm := flag.String("realm", turn_server_realm, "Realm (defaults to \"ScopeAR\")")
	minPort := flag.Int("port-range-min", turn_relay_port_range_min, "lower bounds of the UDP relay endpoints (default is 49152).")
	maxPort := flag.Int("port-range-max", turn_relay_port_range_max, "upper bounds of the UDP relay endpoints (default is 65535).")
	flag.Parse()

	// WARNINGS
	if *publicIP == "127.0.0.1" {
		fmt.Printf("[WARNING] TURN_EXTERNAL_IPV4 is set to the default of `127.0.0.1` !!!\n")
	}
	if *users == "scopear=changeme" {
		fmt.Printf("[WARNING] Using default TURN user and password !!!\n")
	}

	// Start turn server service
	turnServer(publicIP, port, realm, users, minPort, maxPort)
}
