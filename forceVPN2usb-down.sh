#!/bin/bash
# Script para limpiar rutas al desconectar

IPS_FILE="/etc/openvpn/ips.txt"

USB_IFACE=$(ip link show | grep -o 'enx[^:]*' | head -1)
USB_GATEWAY=$(ip route | grep "^default.*$USB_IFACE" | awk '{print $3}')
VPN_TUNNEL=$(ip link show | grep -o 'tun[0-9]*' | head -1)

if [ -z "$VPN_TUNNEL" ]; then
    VPN_TUNNEL="tun2"
fi

# Intentar obtener la IP del servidor
SERVER_IP="$trusted_ip"

if [ -z "$SERVER_IP" ] && [ -n "$REMOTE_HOST" ]; then
    SERVER_IP=$(host "$REMOTE_HOST" | awk '/has address/ {print $4}' | head -1)
fi

if [ -z "$SERVER_IP" ]; then
    SERVER_IP=$(host vpn.aladroc.io | awk '/has address/ {print $4}' | head -1)
fi

# Eliminar ruta del servidor VPN
if [ -n "$SERVER_IP" ] && [ -n "$USB_GATEWAY" ] && [ -n "$USB_IFACE" ]; then
    echo "Eliminando ruta del servidor VPN: $SERVER_IP" | logger -t openvpn-usb
    ip route del $SERVER_IP via $USB_GATEWAY dev $USB_IFACE 2>/dev/null || true
fi

# Eliminar rutas adicionales del archivo
if [ -f "$IPS_FILE" ]; then
    echo "Eliminando rutas adicionales desde $IPS_FILE" | logger -t openvpn-usb
    
    while IFS= read -r line || [ -n "$line" ]; do
        # Ignorar líneas vacías y comentarios
        line=$(echo "$line" | sed 's/#.*//' | xargs)
        
        if [ -n "$line" ]; then
            if [[ $line == tunnel:* ]]; then
                # Ruta por túnel
                IP=$(echo $line | sed 's/^tunnel://')
                echo "Eliminando ruta de túnel: $IP" | logger -t openvpn-usb
                ip route del $IP dev $VPN_TUNNEL 2>/dev/null || true
            else
                # Ruta directa por USB
                echo "Eliminando ruta directa: $line" | logger -t openvpn-usb
                ip route del $line via $USB_GATEWAY dev $USB_IFACE 2>/dev/null || true
            fi
        fi
    done < "$IPS_FILE"
    
    echo "Limpieza de rutas completada" | logger -t openvpn-usb
fi