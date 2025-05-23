data "google_compute_network" "injected_vpc_network" {
  name = var.gcp-vpc-network-name
}

########################################################
# Create a Cloud Router
# Reference: https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_router
resource "google_compute_router" "router_1" {
  name = "${var.terrarium-id}-router-1"
  # description = "my cloud router"
  network = data.google_compute_network.injected_vpc_network.name
  # region  = var.gcp-region

  bgp {
    # you can choose any number in the private range
    # ASN (Autonomous System Number) you can choose any number in the private range 64512 to 65534 and 4200000000 to 4294967294.
    asn               = var.gcp-bgp-asn
    advertise_mode    = "CUSTOM"
    advertised_groups = ["ALL_SUBNETS"]
  }
}

# Create a VPN Gateway
# Note - Two IP addresses will be automatically allocated for each of your gateway interfaces
resource "google_compute_ha_vpn_gateway" "ha_vpn_gw_1" {
  # provider = "google-beta"
  name    = "${var.terrarium-id}-ha-vpn-gw-1"
  network = data.google_compute_network.injected_vpc_network.name
}

########################################################
# From here, Azure's resources are required.
########################################################
# Create a peer VPN gateway with peer VPN gateway interfaces
resource "google_compute_external_vpn_gateway" "external_vpn_gw_1" {
  # provider        = "google-beta"
  name            = "${var.terrarium-id}-azure-side-vpn-gw-1"
  redundancy_type = "TWO_IPS_REDUNDANCY"
  description     = "VPN gateway on Azure side"

  interface {
    id         = 0
    ip_address = azurerm_public_ip.vpn_gw_pub_ip_1.ip_address
  }

  interface {
    id         = 1
    ip_address = azurerm_public_ip.vpn_gw_pub_ip_2.ip_address
  }
}

# Create VPN tunnels between the Cloud VPN gateway and the peer VPN gateway
resource "google_compute_vpn_tunnel" "vpn_tunnel_1" {
  name          = "${var.terrarium-id}-vpn-tunnel-1"
  vpn_gateway   = google_compute_ha_vpn_gateway.ha_vpn_gw_1.self_link
  shared_secret = var.preshared-secret
  # shared_secret                   = azurerm_virtual_network_gateway_connection.gcp_and_azure_cnx_1.shared_key
  peer_external_gateway           = google_compute_external_vpn_gateway.external_vpn_gw_1.self_link
  peer_external_gateway_interface = 0
  router                          = google_compute_router.router_1.name
  ike_version                     = 2
  vpn_gateway_interface           = 0
}

resource "google_compute_vpn_tunnel" "vpn_tunnel_2" {
  name          = "${var.terrarium-id}-vpn-tunnel-2"
  vpn_gateway   = google_compute_ha_vpn_gateway.ha_vpn_gw_1.self_link
  shared_secret = var.preshared-secret
  # shared_secret                   = azurerm_virtual_network_gateway_connection.gcp_and_azure_cnx_2.shared_key
  peer_external_gateway           = google_compute_external_vpn_gateway.external_vpn_gw_1.self_link
  peer_external_gateway_interface = 1
  router                          = google_compute_router.router_1.name
  ike_version                     = 2
  vpn_gateway_interface           = 1
}

########################################################

# Configure interfaces for the VPN tunnels
resource "google_compute_router_interface" "router_interface_1" {
  name     = "${var.terrarium-id}-interface-1"
  router   = google_compute_router.router_1.name
  ip_range = "169.254.21.2/30"
  # ip_range = azurerm_virtual_network_gateway.vpn_gw_1.bgp_settings[0].peering_addresses[0].apipa_addresses[0]

  vpn_tunnel = google_compute_vpn_tunnel.vpn_tunnel_1.name
}

resource "google_compute_router_interface" "router_interface_2" {
  name     = "${var.terrarium-id}-interface-2"
  router   = google_compute_router.router_1.name
  ip_range = "169.254.22.2/30"
  # ip_range = azurerm_virtual_network_gateway.vpn_gw_1.bgp_settings[0].peering_addresses[1].apipa_addresses[0]
  vpn_tunnel = google_compute_vpn_tunnel.vpn_tunnel_2.name
}

########################################################
# Configure BGP sessions 
resource "google_compute_router_peer" "router_peer_1" {
  name   = "${var.terrarium-id}-peer-1"
  router = google_compute_router.router_1.name
  # peer_ip_address           = "169.254.21.1"
  peer_ip_address = azurerm_virtual_network_gateway.vpn_gw_1.bgp_settings[0].peering_addresses[0].apipa_addresses[0]
  # peer_asn                  = var.azure-bgp-asn
  peer_asn                  = azurerm_virtual_network_gateway.vpn_gw_1.bgp_settings[0].asn
  advertised_route_priority = 100
  interface                 = google_compute_router_interface.router_interface_1.name
}

resource "google_compute_router_peer" "router_peer_2" {
  name   = "${var.terrarium-id}-peer-2"
  router = google_compute_router.router_1.name
  # peer_ip_address           = "169.254.22.1"
  peer_ip_address = azurerm_virtual_network_gateway.vpn_gw_1.bgp_settings[0].peering_addresses[1].apipa_addresses[0]
  # peer_asn                  = var.azure-bgp-asn
  peer_asn                  = azurerm_virtual_network_gateway.vpn_gw_1.bgp_settings[0].asn
  advertised_route_priority = 100
  interface                 = google_compute_router_interface.router_interface_2.name
}
