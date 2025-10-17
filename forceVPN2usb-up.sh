#!/bin/bash
# Script para forzar VPN por USB - Versión con rutas por túnel

IPS_FILE="/home/aladroc/.vpn/bv21/ips.txt"

# Detectar interfaz USB (comienza con enx)
USB_IFACE=$(ip link show | grep -o 'enx[^:]*' | head -1)

if [ -z "$USB_IFACE" ]; then
    echo "ERROR: No se detectó interfaz USB tethering (enx*)" | logger -t openvpn-usb
    exit 1
fi

echo "Interfaz USB detectado: $USB_IFACE" | logger -t openvpn-usb

# Obtener el gateway del interfaz USB
USB_GATEWAY=$(ip route | grep "^default.*$USB_IFACE" | awk '{print $3}')

if [ -z "$USB_GATEWAY" ]; then
    USB_SUBNET=$(ip addr show $USB_IFACE | grep "inet " | awk '{print $2}')
    if [ -n "$USB_SUBNET" ]; then
        USB_GATEWAY=$(echo $USB_SUBNET | sed 's/\.[0-9]*\/[0-9]*/.1/')
        echo "Gateway inferido de subnet: $USB_GATEWAY" | logger -t openvpn-usb
    fi
fi

if [ -z "$USB_GATEWAY" ]; then
    echo "ERROR: No se pudo determinar el gateway USB" | logger -t openvpn-usb
    exit 1
fi

echo "Gateway USB: $USB_GATEWAY" | logger -t openvpn-usb

# Obtener IP del servidor VPN
SERVER_IP="$trusted_ip"

if [ -z "$SERVER_IP" ]; then
    if [ -n "$REMOTE_HOST" ]; then
        SERVER_IP=$(host "$REMOTE_HOST" | awk '/has address/ {print $4}' | head -1)
        echo "IP resuelta desde REMOTE_HOST: $SERVER_IP" | logger -t openvpn-usb
    else
        SERVER_IP=$(host vpn.aladroc.io | awk '/has address/ {print $4}' | head -1)
        echo "IP resuelta directamente: $SERVER_IP" | logger -t openvpn-usb
    fi
fi

if [ -z "$SERVER_IP" ]; then
    echo "ERROR: No se pudo determinar la IP del servidor VPN" | logger -t openvpn-usb
    exit 1
fi

echo "Servidor VPN: $SERVER_IP" | logger -t openvpn-usb

# Añadir ruta para el servidor VPN (debe ir directo por USB)
ip route add $SERVER_IP via $USB_GATEWAY dev $USB_IFACE 2>/dev/null || {
    echo "La ruta del servidor VPN ya existe (normal en reconexión)" | logger -t openvpn-usb
}

# Verificar ruta del servidor VPN
ROUTE_CHECK=$(ip route get $SERVER_IP 2>/dev/null)
echo "Ruta servidor VPN: $ROUTE_CHECK" | logger -t openvpn-usb

if echo "$ROUTE_CHECK" | grep -q "$USB_IFACE"; then
    echo "✓ Tráfico VPN forzado por USB exitosamente" | logger -t openvpn-usb
else
    echo "✗ FALLO: La ruta del servidor VPN NO va por USB" | logger -t openvpn-usb
    exit 1
fi

# Procesar archivo de IPs adicionales
if [ -f "$IPS_FILE" ]; then
    echo "Procesando IPs adicionales desde $IPS_FILE" | logger -t openvpn-usb
    
    # Detectar interfaz del túnel OpenVPN
    VPN_TUNNEL=$(ip link show | grep -o 'tun[0-9]*' | head -1)
    
    if [ -z "$VPN_TUNNEL" ]; then
        echo "⚠ ADVERTENCIA: No se detectó túnel VPN (tun*)" | logger -t openvpn-usb
        VPN_TUNNEL="tun2"  # Fallback al nombre conocido
    fi
    
    echo "Túnel VPN detectado: $VPN_TUNNEL" | logger -t openvpn-usb
    
    while IFS= read -r line || [ -n "$line" ]; do
        # Ignorar líneas vacías y comentarios
        line=$(echo "$line" | sed 's/#.*//' | xargs)
        
        if [ -n "$line" ]; then
            # Determinar si va por túnel o directo por USB
            if [[ $line == tunnel:* ]]; then
                # Quitar prefijo "tunnel:" y añadir por el túnel VPN
                IP=$(echo $line | sed 's/^tunnel://')
                echo "Añadiendo ruta por túnel VPN ($VPN_TUNNEL): $IP" | logger -t openvpn-usb
                
                ip route add $IP dev $VPN_TUNNEL 2>/dev/null && {
                    echo "✓ Ruta por túnel añadida: $IP" | logger -t openvpn-usb
                } || {
                    echo "⚠ Ruta por túnel ya existe o error: $IP" | logger -t openvpn-usb
                }
                
                # Verificar
                CHECK=$(ip route get $(echo $IP | cut -d'/' -f1) 2>/dev/null)
                if echo "$CHECK" | grep -q "$VPN_TUNNEL"; then
                    echo "✓ Verificado: $IP va por túnel $VPN_TUNNEL" | logger -t openvpn-usb
                else
                    echo "✗ Advertencia: $IP NO va por túnel" | logger -t openvpn-usb
                fi
                
            else
                # Ruta directa por USB (sin túnel)
                echo "Añadiendo ruta directa por USB: $line" | logger -t openvpn-usb
                
                ip route add $line via $USB_GATEWAY dev $USB_IFACE 2>/dev/null && {
                    echo "✓ Ruta directa añadida: $line" | logger -t openvpn-usb
                } || {
                    echo "⚠ Ruta ya existe o error: $line" | logger -t openvpn-usb
                }
                
                # Verificar
                CHECK=$(ip route get $(echo $line | cut -d'/' -f1) 2>/dev/null)
                if echo "$CHECK" | grep -q "$USB_IFACE"; then
                    echo "✓ Verificado: $line va por USB" | logger -t openvpn-usb
                else
                    echo "✗ Advertencia: $line NO va por USB" | logger -t openvpn-usb
                fi
            fi
        fi
    done < "$IPS_FILE"
    
    echo "Procesamiento de IPs adicionales completado" | logger -t openvpn-usb
else
    echo "Archivo $IPS_FILE no encontrado, solo se enruta el servidor VPN" | logger -t openvpn-usb
fi