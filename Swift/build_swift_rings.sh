#!/bin/bash
set -e

STORAGE_NODES=(172.20.10.8)
KOLLA_SWIFT_BASE_IMAGE="kolla/rocky-source-swift-base:2024.2"
mkdir -p /etc/kolla/config/swift

# object (port 6000)
docker run --rm -v /etc/kolla/config/swift/:/etc/kolla/config/swift/ \
  $KOLLA_SWIFT_BASE_IMAGE swift-ring-builder \
  /etc/kolla/config/swift/object.builder create 10 3 1

for node in ${STORAGE_NODES[@]}; do
  for i in {0..2}; do
    docker run --rm -v /etc/kolla/config/swift/:/etc/kolla/config/swift/ \
      $KOLLA_SWIFT_BASE_IMAGE swift-ring-builder \
      /etc/kolla/config/swift/object.builder add r1z1-${node}:6000/d${i} 1
  done
done

# account (port 6001)
docker run --rm -v /etc/kolla/config/swift/:/etc/kolla/config/swift/ \
  $KOLLA_SWIFT_BASE_IMAGE swift-ring-builder \
  /etc/kolla/config/swift/account.builder create 10 3 1

for node in ${STORAGE_NODES[@]}; do
  for i in {0..2}; do
    docker run --rm -v /etc/kolla/config/swift/:/etc/kolla/config/swift/ \
      $KOLLA_SWIFT_BASE_IMAGE swift-ring-builder \
      /etc/kolla/config/swift/account.builder add r1z1-${node}:6001/d${i} 1
  done
done

# container (port 6002)
docker run --rm -v /etc/kolla/config/swift/:/etc/kolla/config/swift/ \
  $KOLLA_SWIFT_BASE_IMAGE swift-ring-builder \
  /etc/kolla/config/swift/container.builder create 10 3 1

for node in ${STORAGE_NODES[@]}; do
  for i in {0..2}; do
    docker run --rm -v /etc/kolla/config/swift/:/etc/kolla/config/swift/ \
      $KOLLA_SWIFT_BASE_IMAGE swift-ring-builder \
      /etc/kolla/config/swift/container.builder add r1z1-${node}:6002/d${i} 1
  done
done

# Rééquilibrage
for ring in object account container; do
  docker run --rm -v /etc/kolla/config/swift/:/etc/kolla/config/swift/ \
    $KOLLA_SWIFT_BASE_IMAGE swift-ring-builder \
    /etc/kolla/config/swift/${ring}.builder rebalance
done

echo "Terminé."