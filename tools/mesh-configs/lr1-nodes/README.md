# LibreRouter v1 TestMesh Node Configurations

Generated configurations for 3 LibreRouter v1 devices.

## Hardware Configuration

Each LibreRouter v1 has 3 WiFi radios:
- **Radio0 (2.4GHz)**: Client AP + Mesh, 10 dBm power
- **Radio1 (5GHz-1)**: Mesh only, 10 dBm power  
- **Radio2 (5GHz-2)**: DISABLED

## Files Generated

- `lime-node-1` - Configuration for Node 1
- `lime-node-2` - Configuration for Node 2
- `lime-node-3` - Configuration for Node 3
- `gateway-override.conf` - Gateway configuration override
- `deploy.sh` - Automated deployment script
- `README.md` - This file

## Deployment

### Option 1: Automated Deployment
```bash
# Deploy to multiple routers
./deploy.sh deploy-all "10.13.0.1 10.13.0.2 10.13.0.3"

# Deploy single node
./deploy.sh deploy 1 thisnode.info
```

### Option 2: Manual Deployment
```bash
# Copy configuration to router
scp lime-node-1 root@10.13.0.1:/etc/config/lime-node

# Apply configuration
ssh root@10.13.0.1 "lime-config && /etc/init.d/network restart"
```

## Gateway Setup

To designate Node 1 as internet gateway:
```bash
# Copy gateway override to Node 1
scp gateway-override.conf root@10.13.0.1:/tmp/
ssh root@10.13.0.1 "cat /tmp/gateway-override.conf >> /etc/config/lime-node"
ssh root@10.13.0.1 "lime-config && /etc/init.d/network restart"
```

## Verification

```bash
# Check mesh status
./deploy.sh status 10.13.0.1

# Verify connectivity  
./deploy.sh verify 10.13.0.1
```

## Network Details

- **Mesh Name**: TestMesh
- **WiFi Network**: TestMesh.org  
- **WiFi Password**: TestMesh2024!
- **IP Range**: 10.13.0.0/16
- **Mesh Protocol**: BATMAN-adv + BMX6/BMX7 + Babel

## Expected Node IPs

Node IPs are calculated from MAC addresses: 10.13.{MAC5}.{MAC6}

For detailed IP allocation behavior, see: [docs/libremesh/IP-ALLOCATION.md](../../../docs/libremesh/IP-ALLOCATION.md)

If routers have sequential MACs ending in 00:01, 00:02, etc:
- Node 1: 10.13.0.1 (if MAC ends in 00:01)
- Node 2: 10.13.0.2 (if MAC ends in 00:02)
- Node 3: 10.13.0.3 (if MAC ends in 00:03)
