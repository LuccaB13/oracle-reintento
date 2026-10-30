#!/usr/bin/env bash
# Intenta crear lucca-server (VM.Standard.A1.Flex, 1 OCPU / 6 GB, gratis).
# Hace varios intentos por ejecución, separados por 60 segundos.
set -u
INTENTOS=4
OCPUS=1
MEMORIA=6
DISCO=100
NOMBRE=lucca-server

salida() { echo "resultado=$1" >> "$GITHUB_OUTPUT"; }

C=$(grep '^tenancy=' ~/.oci/config | cut -d= -f2 | tr -d '[:space:]')
for estado in RUNNING PROVISIONING STARTING STOPPED; do
  if [ -n "$(oci compute instance list --compartment-id "$C" --display-name "$NOMBRE" --lifecycle-state $estado --query 'data[0].id' --raw-output 2>/dev/null)" ]; then
    echo "$NOMBRE ya existe (estado: $estado). No hace falta seguir."
    salida existe; exit 0
  fi
done

AD=$(oci iam availability-domain list --query 'data[0].name' --raw-output)
SUBNET=$(oci network subnet list --compartment-id "$C" --query 'data[0].id' --raw-output)
IMG=$(oci compute image list --compartment-id "$C" --operating-system "Canonical Ubuntu" \
  --operating-system-version "24.04" --shape VM.Standard.A1.Flex --sort-by TIMECREATED \
  --query 'data[0].id' --raw-output)
echo "AD=$AD"; echo "SUBNET=$SUBNET"; echo "IMG=$IMG"
if [ -z "$AD" ] || [ -z "$SUBNET" ] || [ -z "$IMG" ]; then
  echo "Falta algún dato (AD, SUBNET o IMG). Revisá las llaves o la red en Oracle."; salida error; exit 1
fi

for i in $(seq 1 $INTENTOS); do
  echo "$(date '+%H:%M:%S') Intento $i de $INTENTOS"
  S=$(oci compute instance launch --availability-domain "$AD" --compartment-id "$C" \
    --shape VM.Standard.A1.Flex --shape-config "{\"ocpus\":$OCPUS,\"memoryInGBs\":$MEMORIA}" \
    --image-id "$IMG" --subnet-id "$SUBNET" --assign-public-ip true \
    --display-name "$NOMBRE" --boot-volume-size-in-gbs $DISCO \
    --ssh-authorized-keys-file ~/clave.pub 2>&1)
  if echo "$S" | grep -q '"lifecycle-state"'; then
    echo "LISTO, SERVIDOR CREADO"; salida creado; exit 0
  fi
  if echo "$S" | grep -q 'TooManyRequests'; then
    echo "Oracle pidió esperar (demasiados pedidos)."; salida capacidad; exit 0
  fi
  if ! echo "$S" | grep -qi 'capacity'; then
    echo "OTRO ERROR:"; echo "$S"; salida error; exit 1
  fi
  echo "Sin capacidad todavía."
  [ "$i" -lt "$INTENTOS" ] && sleep 60
done
salida capacidad
exit 0
