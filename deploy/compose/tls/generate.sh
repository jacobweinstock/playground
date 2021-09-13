#!/usr/bin/env bash
# This script handles the generation of the TLS certificates.
# The output is 2 files:
# 1. /certs/${FACILITY:-onprem}/server-key.pem (TLS private key)
# 2. /certs/${FACILITY:-onprem}/bundle.pem (TLS public certificate)

set -xo pipefail

# update_csr will add the sans_ip, as a valid host domain in the csr
update_csr() {
	local sans_ip="$1"
	local csr_file="$2"
	sed -i "/\"hosts\".*/a \    \"${sans_ip}\"," "${csr_file}"
}

# cleanup will remove unneeded files
cleanup() {
	rm -rf ca-key.pem ca.csr ca.pem tinkerbell.csr tinkerbell.pem
}

root_ca() {
	# Generate the root CA key and certificate
	cfssl gencert -initca /code/tls/ca.json | cfssljson -bare ca
}

intermediate_ca() {
	# Generate the intermediate CA key and certificate
	cfssl gencert -initca /code/tls/intermediate-ca.json | cfssljson -bare intermediate_ca
	cfssl sign -ca ca.pem -ca-key ca-key.pem -config /code/tls/cfssl.json -profile intermediate_ca intermediate_ca.csr | cfssljson -bare intermediate_ca
}

host_cert() {
	# Generate the host certificate
	cfssl gencert -ca intermediate_ca.pem -ca-key intermediate_ca-key.pem -config /code/tls/cfssl.json -profile=server /code/tls/host.json | cfssljson -bare tinkerbell
}

gen() {
	local bundle_destination="$1"
	local key_destination="$2"
	# Generate the TLS certificates
	root_ca
	intermediate_ca
	host_cert
	cat tinkerbell.pem intermediate_ca.pem >"${bundle_destination}"
	mv tinkerbell-key.pem "${key_destination}"
}

# main orchestrates the process
main() {
	local sans_ip="$1"
	local csr_file="/code/tls/host.json"
	local bundle_file="/certs/${FACILITY:-onprem}/bundle.pem"
	local server_key_file="/certs/${FACILITY:-onprem}/server-key.pem"

	if ! grep -q "${sans_ip}" "${csr_file}"; then
		update_csr "${sans_ip}" "${csr_file}"
	else
		echo "IP ${sans_ip} already in ${csr_file}"
	fi
	if [ ! -f "${bundle_file}" ] && [ ! -f "${server_key_file}" ]; then
		gen "${bundle_file}" "${server_key_file}"
	else
		echo "Files [${bundle_file}, ${server_key_file}] already exist"
	fi
	cleanup
}

main "$1"
