# LibreMesh IP Allocation System

## Overview

LibreMesh uses a sophisticated automatic IP allocation system that calculates unique IPv4 addresses for each mesh node based on the device's MAC address. This deterministic approach ensures consistent IP assignments across network restarts and enables predictable mesh network topology.

## Core Mechanism

### MAC-to-IP Calculation

LibreMesh calculates node IP addresses using the last two octets of the primary interface MAC address:

```
Node IP = NETWORK.{MAC5}.{MAC6}
```

**Example:**
- Network: `10.13.0.0/16` 
- MAC Address: `dc:9f:db:17:c2:05`
- Calculated IP: `10.13.194.5` (MAC5=194/0xc2, MAC6=5/0x05)

### Implementation Details

The calculation occurs in the LibreMesh configuration system during network initialization:

```lua
-- Simplified IP calculation logic
local mac = get_primary_mac()
local mac5 = tonumber(string.sub(mac, 13, 14), 16)  -- 5th octet
local mac6 = tonumber(string.sub(mac, 16, 17), 16)  -- 6th octet
local node_ip = string.format("%s.%d.%d", network_base, mac5, mac6)
```

## Network Architecture

### IP Range Distribution

LibreMesh partitions the configured network range into distinct segments:

#### 10.13.0.0/16 Example Network
- **Total Address Space**: 65,536 addresses
- **Node Range**: `10.13.0.1` - `10.13.255.254` (65,533 potential nodes)
- **DHCP Client Range**: Configurable subset (e.g., `10.13.200.2` - `10.13.200.199`)
- **Reserved Addresses**: Network (`.0`) and broadcast (`.255`) for each subnet

### Gateway and DHCP Configuration

```uci
config lime 'network'
    option main_ipv4_address '10.13.0.0/16'
    option anygw_dhcp_start '2'        # DHCP starts at .2
    option anygw_dhcp_limit '198'      # 198 DHCP addresses available
```

**DHCP Range Calculation:**
```
DHCP Start: 10.13.{NODE_MAC5}.{anygw_dhcp_start}
DHCP End:   10.13.{NODE_MAC5}.{anygw_dhcp_start + anygw_dhcp_limit - 1}
```

## Multi-Node Deployment Scenarios

### Sequential MAC Addresses

When LibreRouter devices have sequential MAC addresses:

| Device | MAC Address | Calculated IP | DHCP Range |
|--------|-------------|---------------|------------|
| Node 1 | `dc:9f:db:17:00:01` | `10.13.0.1` | `10.13.0.2` - `10.13.0.199` |
| Node 2 | `dc:9f:db:17:00:02` | `10.13.0.2` | `10.13.0.2` - `10.13.0.199` |
| Node 3 | `dc:9f:db:17:00:03` | `10.13.0.3` | `10.13.0.2` - `10.13.0.199` |

**DHCP Conflict Resolution:**
- All nodes share the same DHCP pool in `10.13.0.x` subnet
- BATMAN-adv anycast gateway prevents conflicts
- First responding node serves DHCP requests

### Random MAC Addresses  

With random MAC addresses, nodes distribute across the IP space:

| Device | MAC Address | Calculated IP | DHCP Range |
|--------|-------------|---------------|------------|
| Node A | `dc:9f:db:17:c2:05` | `10.13.194.5` | `10.13.194.2` - `10.13.194.199` |
| Node B | `dc:9f:db:17:8a:f3` | `10.13.138.243` | `10.13.138.2` - `10.13.138.199` |
| Node C | `dc:9f:db:17:45:12` | `10.13.69.18` | `10.13.69.2` - `10.13.69.199` |

**Advantages:**
- Natural load distribution across IP space
- Each node manages distinct DHCP subnet
- Reduced chance of IP conflicts

## Network Behavior Analysis

### Boot Sequence

1. **Interface Initialization**: Primary interface gets MAC-calculated IP
2. **Mesh Protocol Start**: BATMAN-adv, Babel, BMX6/BMX7 initialize
3. **Gateway Discovery**: Anycast gateway coordination begins
4. **DHCP Service**: Node starts serving its calculated DHCP range
5. **Mesh Convergence**: Routing tables synchronize across mesh

### Connectivity Timeline

**Immediate (0-30 seconds):**
- Node gets unique IP address
- Local DHCP service starts
- Radio interfaces activate

**Short-term (30-120 seconds):**
- Mesh protocols discover neighbors
- Routing tables begin convergence  
- Gateway election occurs

**Long-term (2-10 minutes):**
- Full mesh topology established
- Optimal routing paths calculated
- Network reaches stable state

### Gateway Selection

LibreMesh uses anycast gateway with automatic election:

```uci
config lime 'proto' 'batadv'
    option gw_mode 'client'          # Default: all nodes as clients
    option gw_sel_class '20'         # Gateway selection preference

# Override for gateway node:
config lime 'proto' 'batadv'  
    option gw_mode 'server'          # Designated gateway
    option gw_sel_class '255'        # Highest priority
    option gw_bandwidth '50000/10000' # Advertised bandwidth
```

## Deployment Considerations

### Planning Node Deployment

**For Sequential Deployment:**
1. Plan IP allocation based on expected MAC addresses
2. Configure appropriate DHCP ranges to avoid conflicts
3. Test connectivity between adjacent IP ranges
4. Verify gateway accessibility from all nodes

**For Random Deployment:**
1. Prepare for distributed IP allocation
2. Monitor DHCP pool usage per subnet
3. Plan gateway placement for optimal coverage
4. Test inter-subnet routing performance

### IP Allocation Verification

```bash
# Check node IP allocation
ip addr show br-lan | grep 'inet ' | awk '{print $2}'

# Verify MAC-to-IP calculation
MAC=$(cat /sys/class/net/eth0/address)
echo "MAC: $MAC"
MAC5=$(echo $MAC | cut -d: -f5)
MAC6=$(echo $MAC | cut -d: -f6)
EXPECTED_IP="10.13.$((0x$MAC5)).$((0x$MAC6))"
echo "Expected IP: $EXPECTED_IP"

# Check DHCP range
uci get lime.network.anygw_dhcp_start
uci get lime.network.anygw_dhcp_limit
```

### Troubleshooting IP Conflicts

**Conflict Detection:**
```bash
# Check for duplicate IPs in mesh
batctl ping -c 3 $(ip route | grep br-lan | awk '{print $9}')

# Monitor DHCP leases
cat /tmp/dhcp.leases

# Verify mesh topology
batctl o  # Originators table
batctl n  # Neighbors table
```

**Resolution Strategies:**
1. **MAC Address Conflicts**: Verify unique MAC addresses across devices
2. **Configuration Errors**: Check lime-community and lime-node consistency  
3. **Network Partitioning**: Verify mesh connectivity and routing
4. **DHCP Pool Exhaustion**: Adjust `anygw_dhcp_limit` values

## Integration with Configuration System

### Hierarchical Configuration Impact

LibreMesh's 4-level configuration hierarchy affects IP allocation:

1. **lime-defaults**: Base network configuration
2. **lime-community**: Community-wide IP ranges and DHCP settings
3. **lime-MAC**: Device-specific overrides (rarely used for IP)
4. **lime-node**: Node-specific IP and DHCP customizations

**Example Configuration Override:**
```uci
# lime-community: Base network
config lime 'network'
    option main_ipv4_address '10.13.0.0/16'
    option anygw_dhcp_start '2'
    option anygw_dhcp_limit '198'

# lime-node: Node-specific DHCP adjustment  
config lime 'network'
    option anygw_dhcp_start '50'     # Start DHCP at .50
    option anygw_dhcp_limit '100'    # Limit to 100 addresses
```

### Template Variables

LibreMesh supports template variables in configuration:

- `%Mn`: n-th byte of primary MAC address (1-6)
- `%Nn`: n-th nibble of primary MAC address (1-12)  
- `%H`: Full hostname

**Usage Example:**
```uci
config lime 'system'
    option hostname 'Node-%M4%M5%M6'  # Results in 'Node-17c205'
```

## Performance Characteristics

### Scaling Considerations

**Network Size Impact:**
- **Small Networks (< 50 nodes)**: Minimal IP management overhead
- **Medium Networks (50-200 nodes)**: DHCP coordination becomes important
- **Large Networks (200+ nodes)**: Consider network segmentation

**Protocol Overhead:**
- **BATMAN-adv**: Efficient for networks up to 100-200 nodes
- **Babel**: Better scaling for larger networks
- **BMX6/BMX7**: Hybrid approach for mixed topologies

### Optimization Strategies

**DHCP Pool Management:**
```uci
# Optimize DHCP pools for node density
config lime 'network'
    option anygw_dhcp_start '100'     # Higher start for sparse networks
    option anygw_dhcp_limit '50'      # Smaller pools for dense networks
```

**Gateway Placement:**
```uci
# Strategic gateway configuration
config lime 'proto' 'batadv'
    option gw_sel_class '50'          # Moderate gateway preference
    option gw_bandwidth '100000/20000' # Realistic bandwidth advertisement
```

## Advanced Topics

### Custom IP Allocation

For non-standard IP allocation requirements:

```bash
# Override automatic IP calculation
uci set network.lan.ipaddr='10.13.100.50'
uci set network.lan.netmask='255.255.0.0'
uci commit network
/etc/init.d/network restart
```

### Multi-Network Scenarios

LibreMesh supports multiple networks per node:

```uci
config lime 'network' 'mesh_a'
    option main_ipv4_address '10.13.0.0/16'
    option vlan_id '13'

config lime 'network' 'mesh_b'  
    option main_ipv4_address '172.16.0.0/16'
    option vlan_id '16'
```

### IPv6 Considerations

LibreMesh also supports IPv6 with similar MAC-based allocation:

```uci
config lime 'network'
    option main_ipv6_address 'fd13::/64'
```

IPv6 addresses use EUI-64 format derived from MAC addresses.

## Reference Implementation

### Verification Scripts

Complete verification tools are available in the lime-dev repository:

- **IP Allocation Checker**: `tools/mesh-configs/verify-mesh-deployment.sh`
- **Node Generator**: `tools/mesh-configs/generate-lr1-nodes.sh`
- **Network Analysis**: Integration with existing lime-dev tools

### Configuration Examples

Working configuration examples:

- **TestMesh Configuration**: `tools/mesh-configs/lime-community-testmesh`
- **Node Templates**: `tools/mesh-configs/lr1-nodes/`
- **Gateway Overrides**: Gateway configuration patterns

## Related Documentation

- **[Hierarchical Configuration System](HIERARCHICAL-CONFIGURATION.md)** - Understanding LibreMesh configuration management
- **[lime-dev README](../../README.md)** - Development environment setup
- **[Mesh Configuration Tools](../../tools/mesh-configs/)** - Practical deployment tools

---

*This documentation is based on LibreMesh 2023.05+ behavior and has been tested with lime-dev development environment. For the latest LibreMesh features and updates, consult the [official LibreMesh documentation](https://libremesh.org/docs).*