package state

import (
	"crypto/md5"
	"encoding/hex"
	"list"
	"strings"
	"path"
)

#ConfigInput: {
	clusterName: string & !=""
	outputDir:   string & !=""
	namespace:   string & !=""
	arch:        "amd64" | "arm64"
	bootMode:    "netboot" | "isoboot"
	externalTinkerbell: bool | *false
	counts: {
		controlPlanes: int & >=1
		workers:       int & >=0
		spares:        int & >=0
	}
	versions: {
		capt:    string & !=""
		chart:   string & !=""
		kube:    =~"^v[0-9]+\\.[0-9]+\\.[0-9]+$"
		os:      string | int
		kubevip: string | number
	}
	capt: providerRepository: string & !=""
	chart: {
		location: string & !=""
		// null: a key written with no value parses that way, and means absent.
		extraVars?: null | [...string]
	}
	os: {
		registry: string & !=""
	}
	vm: {
		baseName:           string & !=""
		cpusPerVM:          int & >0
		memInMBPerVM:       int & >0
		diskSizeInGBPerVM:  int & >0
		diskPath:           string & !=""
	}
	virtualBMC: {
		image: string & !=""
	}
	captainos?: null | {
		kernelVersion: string & !=""
	}
}

config: #ConfigInput

cwd:        string | *""             @tag(cwd)
sshPubKey:  string | *""             @tag(sshPubKey)
_gatewayIP: string | *""             @tag(gatewayIP)
_bridge:    string | *""             @tag(bridgeName)

// Identifies one playground among however many share the host. The caller
// derives it from the state file's path (see Taskfile.yaml#INSTANCE_ID), so it
// is stable for the life of a playground without anything having to store it,
// and distinct for anything driven by a different state file.
//
// Left empty the playground still works, it just takes the unsuffixed names it
// always used -- which is the right default for a host running only one.
instanceID: string | *""             @tag(instanceID)

_suffix: [
	if instanceID != "" {"-\(instanceID)"},
	"",
][0]

// Names of everything the host, rather than a cluster, has to keep distinct:
// docker networks and containers, KinD clusters and libvirt domains all share
// one namespace per machine. Kubernetes objects are not here -- they are
// already scoped by the cluster they live in.
_names: {
	network:     "\(config.clusterName)\(_suffix)"
	kindCluster: "\(config.clusterName)\(_suffix)"
	tinkCluster: "\(config.clusterName)\(_suffix)-tinkerbell"
}

// Libvirt domains are host-global, and their names drive the VM MACs and disk
// image filenames, so prefixing here keeps all three distinct at once.
_vmPrefix: [
	if instanceID != "" {"\(instanceID)-\(config.vm.baseName)"},
	config.vm.baseName,
][0]

_outputDirBase: [
	if path.IsAbs(config.outputDir, path.Unix) {config.outputDir},
	if cwd != "" {path.Join([cwd, config.outputDir], path.Unix)},
	config.outputDir,
][0]

// Instance-scoped so two playgrounds pointed at the same config still keep
// their kubeconfigs, certs and rendered manifests apart.
_outputDir: [
	if instanceID != "" {path.Join([_outputDirBase, instanceID], path.Unix)},
	_outputDirBase,
][0]

_totalNodes: config.counts.controlPlanes + config.counts.workers + config.counts.spares

_osVersion: strings.Replace("\(config.versions.os)", ".", "", -1)

// Static because one vBMC container serves every playground on the host: it is
// reached over each playground's own docker network, so it needs no per-
// instance name, and one container can hold only one credential pair.
_vbmcContainer: "capt-vbmc"
_vbmcUser:      "root"
_vbmcPass:      "calvin"

_indexes: list.Range(1, _totalNodes+1, 1)

#mac: {
	_input: string
	_sum:   md5.Sum(_input + "\n")
	_hex:   strings.Split(hex.Encode(_sum), "")
	out:    "02:" + strings.Join([
		_hex[0] + _hex[1],
		_hex[2] + _hex[3],
		_hex[4] + _hex[5],
		_hex[6] + _hex[7],
		_hex[8] + _hex[9],
	], ":")
}

#role: {
	_idx: int
	out: [
		if _idx <= config.counts.controlPlanes {"control-plane"},
		if _idx <= config.counts.controlPlanes+config.counts.workers {"worker"},
		"spare",
	][0]
}

_gwParts: strings.Split(_gatewayIP, ".")
_nodeIPBase: [
	if _gatewayIP == "" {""},
	"\(_gwParts[0]).\(_gwParts[1]).10.20",
][0]
_baseLastOctet: 20

#offsetIP: {
	_offset: int
	out: [
		if _gatewayIP == "" {""},
		"\(_gwParts[0]).\(_gwParts[1]).10.\(_baseLastOctet+_offset)",
	][0]
}

_podCIDR: [
	if _gatewayIP == "" {""},
	"\(_gwParts[0]).100.0.0/16",
][0]

_details: {
	for i in _indexes {
		"\(_vmPrefix)\(i)": {
			mac:  (#mac & {_input: "\(_vmPrefix)\(i)"}).out
			bmc: port: 6230 + i
			role: (#role & {_idx: i}).out
			if _gatewayIP != "" {
				ip:      (#offsetIP & {_offset: i}).out
				gateway: _gatewayIP
			}
		}
	}
}

out: {
	// clusterName stays the CAPI workload cluster's name. It is a Kubernetes
	// object inside a cluster of its own, so it never has to be unique on the
	// host -- `names` covers everything that does.
	clusterName: config.clusterName
	instance:    instanceID
	names:       _names
	outputDir:   _outputDir
	namespace:   config.namespace
	arch:        config.arch
	bootMode:    config.bootMode
	externalTinkerbell: config.externalTinkerbell
	counts:   config.counts
	versions: config.versions
	capt:     config.capt
	// chart.location is supplied by cue/state/mirror_extension.cue (so the
	// optional registry mirror can rewrite it). Pass through everything else.
	chart: {
		if config.chart.extraVars != _|_ if config.chart.extraVars != null {
			extraVars: config.chart.extraVars
		}
	}
	os: {
		// os.registry is supplied by cue/state/mirror_extension.cue.
		sshKey:  sshPubKey
		version: _osVersion
	}
	vm: {
		baseName:          _vmPrefix
		cpusPerVM:         config.vm.cpusPerVM
		memInMBPerVM:      config.vm.memInMBPerVM
		diskSizeInGBPerVM: config.vm.diskSizeInGBPerVM
		diskPath:          config.vm.diskPath
		details:           _details
	}
	virtualBMC: {
		containerName: _vbmcContainer
		// virtualBMC.image is supplied by cue/state/mirror_extension.cue.
		// One vBMC is shared by every playground on the host, so it has one
		// credential pair; these are fixed rather than configurable.
		user: _vbmcUser
		pass: _vbmcPass
	}
	if config.captainos != _|_ if config.captainos != null {
		captainos: config.captainos
	}
	totalNodes: _totalNodes
	kind: {
		kubeconfig: "\(_outputDir)/kind.kubeconfig"
		if _gatewayIP != "" {
			gatewayIP:  _gatewayIP
			nodeIPBase: _nodeIPBase
		}
		if _bridge != "" {
			bridgeName: _bridge
		}
		// Second KinD cluster used as the Tinkerbell stack target when
		// `externalTinkerbell: true`. Same docker network as the management
		// cluster (the playground's own, see tasks/Taskfile-network.yaml) so
		// pods in the management cluster can reach the Tinkerbell API server
		// via the container IP (see scripts/create_external_kubeconfig_secret.sh).
		if config.externalTinkerbell {
			tinkerbell: {
				clusterName: _names.tinkCluster
				kubeconfig:  "\(_outputDir)/tinkerbell-kind.kubeconfig"
			}
		}
	}
	if _gatewayIP != "" {
		tinkerbell: {
			vip:       (#offsetIP & {_offset: _totalNodes + 51}).out
			hookosVip: (#offsetIP & {_offset: _totalNodes + 50}).out
		}
		cluster: {
			controlPlane: vip: (#offsetIP & {_offset: _totalNodes + 52}).out
			podCIDR: _podCIDR
		}
	}
}
