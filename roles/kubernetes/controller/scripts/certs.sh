IS_ANSIBLE=${1}
if [[ ! -z "${1}" ]] && [[ "${1}" == "ansible" ]]; then
  IS_ANSIBLE='TRUE'
  HOSTNAME=`hostname`
  KUBE_NODES=(${HOSTNAME})
  KUBE_MASTERS=(${HOSTNAME})
  PREFIX=''
  if [[ ! -z "${2}" ]] && [[ "${2}" == "ca" ]]; then
      ANSIBLE_CA_FOLDER=${3}
    IS_ANSIBLE_CA='TRUE'
  else
      HOST_NET=${2}
      KUBE_SVC_NET=${3}
      KUBE_CIDR_NET=${4}
  fi
else
  KUBE_NODES=(node1 node2 node3)
  KUBE_MASTERS=(master1 master2 master3)
  HOST_NET='192.168.0.0'
  KUBE_SVC_NET='10.32.0.0'
  KUBE_CIDR_NET='10.0.0.0'
  PREFIX='/home/ipa/artemov'
fi

PKI_FOLDER=${PREFIX}'/etc/kubernetes/pki'

if [[ "${IS_ANSIBLE_CA}" == 'TRUE' ]]; then
  echo -e "\033[33mStarted generating of CA ONLY!\033[0m"
  PREFIX=${ANSIBLE_CA_FOLDER}
  PKI_FOLDER=${PREFIX}
fi

PKI_KEY_FOLDER=${PKI_FOLDER}'/key'
PKI_KEY_CONFIG_FOLDER=${PKI_KEY_FOLDER}'/config'
PKI_CA_FOLDER=${PKI_FOLDER}'/ca'
PKI_CA_CONFIG_FOLDER=${PKI_CA_FOLDER}/config
PKI_CA_CONFIG=${PKI_CA_CONFIG_FOLDER}/ca.json
PKI_CA_PEM=${PKI_CA_FOLDER}/ca.pem
PKI_CA_KEY=${PKI_CA_FOLDER}/ca-key.pem
PKI_CA_EXPIRE='8760h'
PKI_C='RU'
PKI_L='Moscow'
PKI_ST='Moscow'




###Install and check hash

function check_cfssl() {
  NAME=${1}
  REMOTE_HASH=`curl --silent https://pkg.cfssl.org/R1.2/SHA256SUMS | awk '/'${NAME}'_linux-amd64/ {print $1}'`
  LOCAL_HASH=`sha256sum ${PREFIX}/bin/${NAME} | awk '{print $1}'`
  if [[ "${REMOTE_HASH}" != "${LOCAL_HASH}" ]]; then
    echo -e "\033[33mHash summ of ${NAME} don't match!\033[0m"
    echo -e "Remote:\t" ${REMOTE_HASH}
    echo -e "Local:\t" ${LOCAL_HASH}
    return 1
  else
    return 0
  fi
}

for current_bin in cfssl cfssljson; do
  echo "Check ${current_bin} file..."
  mkdir -p ${PREFIX}/bin
  if [ -f ${PREFIX}/bin/${current_bin} ]; then
    check_cfssl ${current_bin}
    if [[ ! $?  -eq 0 ]]; then
          echo "Remove current ${current_bin}"
      rm -rfv ${PREFIX}/bin/${current_bin}
      echo "Download ${current_bin} from https://pkg.cfssl.org/R1.2/${current_bin}_linux-amd64"
      wget -q --https-only --no-dns-cache --timestamping https://pkg.cfssl.org/R1.2/${current_bin}_linux-amd64 --output-document=${PREFIX}/bin/${current_bin}
      check_cfssl ${current_bin}
      if [[ ! $?  -eq 0 ]]; then
        echo -e "\033[33mError binary file!\033[0m"
        exit 1
      else
        chmod 750 ${PREFIX}/bin/${current_bin}
        echo "${current_bin} reinstalled"
      fi
    else
      echo "${current_bin} already installed"
    fi
  else
    echo "Download ${current_bin} from https://pkg.cfssl.org/R1.2/cfssl_linux-amd64"
    wget -q --https-only --no-dns-cache --timestamping https://pkg.cfssl.org/R1.2/${current_bin}_linux-amd64 --output-document=${PREFIX}/bin/${current_bin}
    check_cfssl ${current_bin}
    if [[ ! $?  -eq 0 ]]; then
      echo -e "\033[33mError binary file!\033[0m"
      exit 1
    else
      chmod 750 ${PREFIX}/bin/${current_bin}
      echo "${current_bin} installed"
    fi
  fi
done

### Check and generating CA
if [ ! -f ${PKI_CA_PEM} ]; then
  if [ -d "$DIRECTORY" ]; then
    rm -rfv ${PKI_FOLDER}
  fi

  mkdir -p ${PKI_FOLDER} ${PKI_CA_FOLDER}/ ${PKI_CA_CONFIG_FOLDER}
  cat > ${PKI_CA_CONFIG} <<EOF
{
  "signing": {
    "default": {
      "expiry": "${PKI_CA_EXPIRE}"
    },
    "profiles": {
      "kubernetes": {
        "usages": ["signing", "key encipherment", "server auth", "client auth"],
        "expiry": "${PKI_CA_EXPIRE}"
      }
    }
  }
}
EOF
  cat > ${PKI_CA_FOLDER}/config/csr.json <[ ${PREFIX}/bin/cfssljson -bare ${PKI_CA_FOLDER}/ca
fi

if [[ "${IS_ANSIBLE_CA}" == 'TRUE' ]]; then
  echo 'CA pem and key generated'
  exit 0
fi

if [ ! -f ${PKI_CA_PEM} ]; then
  echo -e "\033[33mNo CA file. Ooops\033[0m"
  exit 1
fi

### Generating keys
mkdir -p ${PKI_KEY_FOLDER} ${PKI_KEY_FOLDER}/config
function gen_csr_config() {
  PKI_NAME=${1}
  PKI_CN=${2}
  PKI_O=${3}
  cat ](EOF
{
  "CN": "Kubernetes",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "${PKI_C}",
      "L": "${PKI_L}",
      "O": "Kubernetes",
      "OU": "CA",
      "ST": "${PKI_ST}"
    }
  ]
}
EOF
  ${PREFIX}/bin/cfssl gencert -initca ${PKI_CA_FOLDER}/config/csr.json ) ${PKI_KEY_CONFIG_FOLDER}/${PKI_NAME}-csr.json <<EOF
{
  "CN": "${PKI_CN}",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "${PKI_C}",
      "L": "${PKI_L}",
      "O": "${PKI_O}",
      "OU": "Kubernetes The Hard Way",
      "ST": "${PKI_ST}"
    }
  ]
}
EOF
}

#### Kubectl cert
gen_csr_config 'admin' 'admin' 'system:masters'
${PREFIX}/bin/cfssl gencert -ca=${PKI_CA_PEM} -ca-key=${PKI_CA_KEY} -config=${PKI_CA_CONFIG} -profile=kubernetes ${PKI_KEY_CONFIG_FOLDER}/admin-csr.json | \
  ${PREFIX}/bin/cfssljson -bare ${PKI_KEY_FOLDER}/admin

#### Kubelet certs
##Ansible: NAME of cert is HOSTNAME.pem and HOSTNAME-key.pem!
for instance in ${KUBE_NODES[@]}; do
  gen_csr_config ${instance} ${instance} "system:node:${instance}"
  ${PREFIX}/bin/cfssl gencert -ca=${PKI_CA_PEM} -ca-key=${PKI_CA_KEY} -config=${PKI_CA_CONFIG} -hostname=${instance},${HOST_NET},${KUBE_SVC_NET},${KUBE_CIDR_NET} \
                -profile=kubernetes ${PKI_KEY_CONFIG_FOLDER}/${instance}-csr.json | ${PREFIX}/bin/cfssljson -bare ${PKI_KEY_FOLDER}/${instance}
done

#### 
gen_csr_config 'kube-controller-manager' 'system:kube-controller-manager' 'system:kube-controller-manager'
${PREFIX}/bin/cfssl gencert -ca=${PKI_CA_PEM} -ca-key=${PKI_CA_KEY} -config=${PKI_CA_CONFIG} -profile=kubernetes ${PKI_KEY_CONFIG_FOLDER}/kube-controller-manager-csr.json | \
  ${PREFIX}/bin/cfssljson -bare ${PKI_KEY_FOLDER}/kube-controller-manager

gen_csr_config 'kube-proxy' 'system:kube-proxy' 'system:node-proxier'
${PREFIX}/bin/cfssl gencert -ca=${PKI_CA_PEM} -ca-key=${PKI_CA_KEY} -config=${PKI_CA_CONFIG} -profile=kubernetes ${PKI_KEY_CONFIG_FOLDER}/kube-proxy-csr.json | \
  ${PREFIX}/bin/cfssljson -bare ${PKI_KEY_FOLDER}/kube-proxy

gen_csr_config 'kube-scheduler' 'system:kube-scheduler' 'system:kube-scheduler'
${PREFIX}/bin/cfssl gencert -ca=${PKI_CA_PEM} -ca-key=${PKI_CA_KEY} -config=${PKI_CA_CONFIG} -profile=kubernetes ${PKI_KEY_CONFIG_FOLDER}/kube-scheduler-csr.json | \
  ${PREFIX}/bin/cfssljson -bare ${PKI_KEY_FOLDER}/kube-scheduler

#### Early name was kubernetes.pem
#### KUBE-API certs
##Ansible: NAME of cert is kube-api-HOSTNAME.pem and kube-api-HOSTNAME-key.pem!
for master in ${KUBE_MASTERS[@]}; do
gen_csr_config "kube-api-${master}" 'kubernetes' 'Kubernetes'
${PREFIX}/bin/cfssl gencert -ca=${PKI_CA_PEM} -ca-key=${PKI_CA_KEY} -config=${PKI_CA_CONFIG} -hostname=${master},kubernetes.default,127.0.0.1,${HOST_NET},${KUBE_SVC_NET},${KUBE_CIDR_NET} \
  -profile=kubernetes ${PKI_KEY_CONFIG_FOLDER}/kube-api-${master}-csr.json | ${PREFIX}/bin/cfssljson -bare ${PKI_KEY_FOLDER}/kube-api-${master}
done

### Early name was service-account
gen_csr_config 'kube-service-account' 'service-accounts' 'Kubernetes'
${PREFIX}/bin/cfssl gencert -ca=${PKI_CA_PEM} -ca-key=${PKI_CA_KEY} -config=${PKI_CA_CONFIG} -profile=kubernetes ${PKI_KEY_CONFIG_FOLDER}/kube-service-account-csr.json | \
  ${PREFIX}/bin/cfssljson -bare ${PKI_KEY_FOLDER}/kube-service-account

rm -rfv ${PKI_KEY_FOLDER}/*.csr