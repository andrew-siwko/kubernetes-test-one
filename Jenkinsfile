pipeline {
    agent { label 'docker-builder' }

    environment {
        // Use the domain name your K8s cluster uses to resolve the registry
        REGISTRY_DOMAIN = 'kregistry.siwko.org:5000'
        IMAGE_NAME      = 'python-server'
        IMAGE_TAG       = "${env.BUILD_NUMBER}"
        DEPLOYMENT_NAME = 'python-server-deployment'
        RETAIN_COUNT    = '10'
    }

    stages {
        stage('Checkout Code') {
            steps {
                // Jenkins automatically pulls the code from Git here
                checkout scm
            }
        }

        stage('Build & Push Multi-Arch Image') {
            steps {
                echo "Building & pushing multi-arch image: ${REGISTRY_DOMAIN}/${IMAGE_NAME}:${IMAGE_TAG}..."
                // Cluster has both amd64 (RHEL) and arm64 (Orange Pi) nodes, so the image
                // manifest must cover both platforms. Multi-platform images can't be
                // docker-loaded locally, so build and push happen in one buildx step.
                // Reuse the builder across runs (preserves BuildKit's layer cache and avoids
                // tearing down a builder another concurrent job may be using); only create
                // it if missing. The docker-container driver runs BuildKit in its own
                // container, isolated from the host daemon.json insecure-registries setting,
                // so it needs its own config -- baked in once via a fixed host path, not the
                // repo, so any project's Jenkinsfile can reuse the same line.
                sh "docker buildx inspect multiarch-builder >/dev/null 2>&1 || docker buildx create --name multiarch-builder --driver docker-container --config /etc/buildkit/buildkitd.toml --bootstrap"
                sh "docker buildx use multiarch-builder"
                sh """
                    docker buildx build \
                      --platform linux/amd64,linux/arm64 \
                      -t ${REGISTRY_DOMAIN}/${IMAGE_NAME}:${IMAGE_TAG} \
                      -t ${REGISTRY_DOMAIN}/${IMAGE_NAME}:latest \
                      --push .
                """
            }
        }

        stage('Deploy example to Kubernetes') {
            steps {
                echo "Applying manifests and updating deployment image..."
                // Always apply the manifests first so Service or ConfigMap changes take effect
                sh "kubectl apply -f k8s/rbac.yaml"
                // Always apply the manifests first so Service or ConfigMap changes take effect.
                // deployment.yaml has no hardcoded registry -- substitute the same
                // REGISTRY_DOMAIN used for the build so there's one source of truth.
                sh "sed 's|REGISTRY_DOMAIN_PLACEHOLDER|${REGISTRY_DOMAIN}|g' k8s/deployment.yaml | kubectl apply -f -"
                // Then update the image to the exact build tag
                sh "kubectl set image deployment/${DEPLOYMENT_NAME} app-container=${REGISTRY_DOMAIN}/${IMAGE_NAME}:${IMAGE_TAG}"
            }
        }       

        stage('Label Cluster Nodes by Physical Host') {
            steps {
                echo "Labeling nodes with their physical host, so pods can be spread across real hardware..."
                sh """
                    kubectl label node kcontrol01 knode01 knode02 knode03 knode04 physical-host=winbox-1 --overwrite
                    kubectl label node knode05 knode06 knode07 knode08 physical-host=winbox-2 --overwrite
                    kubectl label node orangepizero3 physical-host=orangepi --overwrite
                """
            }
        }

        stage('Label Cluster Nodes by DB Host Group') {
            steps {
                // Four groups of two nodes each, two groups per physical host, so a
                // required podAntiAffinity on this label can place exactly one
                // postgres instance per group -- 4 groups for 4 instances means no
                // group is ever oversubscribed, unlike physical-host (only 2 values)
                // which would strand a 3rd/4th instance with nowhere left to
                // schedule under a required constraint. Two groups per physical
                // host also means a single-VM failure only ever takes out one
                // instance, not two, since the paired group is a different VM.
                // Must run before the CNPG Cluster manifest is applied -- the
                // scheduler needs this label to already exist on nodes before a
                // Cluster spec can require spreading across its values.
                echo "Labeling nodes with db-host-group, so postgres can require one instance per group..."
                sh """
                    kubectl label node knode01 knode02 db-host-group=winbox1-a --overwrite
                    kubectl label node knode03 knode04 db-host-group=winbox1-b --overwrite
                    kubectl label node knode05 knode06 db-host-group=winbox2-a --overwrite
                    kubectl label node knode07 knode08 db-host-group=winbox2-b --overwrite
                """
            }
        }

        stage('Apply infrastructure deployments') {
            steps {
                sh "kubectl apply -f k8s/metal-lb-config.yaml"
            }
        }
        stage('Deploy External DNS to Kubernetes') {
            steps {
                echo "Applying external dns deployment"
                sh "kubectl apply -f k8s/external-dns-linode.yaml"
            }
        }

        stage('Apply CoreDNS resilience fix') {
            steps {
                echo "Enforcing physical-host spread for CoreDNS (kube-system)"
                // Re-asserts kubeadm's CoreDNS Deployment with one change: the
                // existing physical-host topologySpreadConstraint's
                // whenUnsatisfiable is DoNotSchedule instead of the kubeadm
                // default ScheduleAnyway, so a physical host outage can't leave
                // all 3 replicas stranded on the surviving hosts. See the
                // comment in coredns-deployment.yaml for the incident that
                // prompted this. Depends on the "coredns" ConfigMap/ServiceAccount
                // kubeadm already created -- not reproduced here.
                sh "kubectl apply -f k8s/coredns-deployment.yaml"
            }
        }

        stage('Deploy CNPG Operator to Kubernetes') {
            steps {
                echo "Applying CloudNativePG operator (CRDs, RBAC, webhooks, controller manager)"
                // Pinned to the upstream v1.30.0 release manifest -- bump the file and this
                // comment together when upgrading. Idempotent: no-op if the cluster already
                // matches, since this is the same bundle the operator was originally installed from.
                // --server-side is required, not optional: the CNPG CRDs (esp.
                // clusters.postgresql.cnpg.io) are big enough that client-side apply's
                // last-applied-configuration annotation exceeds Kubernetes' 256KB annotation
                // limit and fails.
                sh "kubectl apply --server-side --force-conflicts -f k8s/cnpg-operator.yaml"
            }
        }

        stage('Deploy CNPG Cluster to Kubernetes') {
            steps {
                echo "Applying the prod-postgres Cluster resource"
                // Must run after both the operator (needs the CRD to exist) and the
                // "Label Cluster Nodes by DB Host Group" stage (the Cluster's
                // affinity requires spreading across db-host-group values, which
                // only means something once nodes actually carry that label).
                sh "kubectl apply -f k8s/prod-postgres-cluster.yaml"
            }
        }

        stage('Label nodes for Longhorn zone') {
            steps {
                // Longhorn hard-codes its replica failure-domain ("zone")
                // source to the k8s node label topology.kubernetes.io/zone --
                // confirmed via current docs, not configurable to reuse the
                // physical-host label directly. This just mirrors
                // physical-host's existing values under the key Longhorn
                // actually reads. Must run before any real Longhorn volume
                // is created so replicas schedule with correct zone info
                // from the start.
                echo "Labeling nodes with topology.kubernetes.io/zone, so Longhorn can spread replicas across physical hosts..."
                sh """
                    kubectl label node kcontrol01 knode01 knode02 knode03 knode04 topology.kubernetes.io/zone=winbox-1 --overwrite
                    kubectl label node knode05 knode06 knode07 knode08 topology.kubernetes.io/zone=winbox-2 --overwrite
                """
            }
        }

        stage('Install Longhorn') {
            steps {
                echo "Applying Longhorn (namespace, CRDs, manager/CSI DaemonSets+Deployments)"
                // Pinned to the upstream v1.12.0 release manifest -- bump the file and this
                // comment together when upgrading. Requires scripts/longhorn-node-prep.sh to
                // have already been run by hand on every node once (iscsid etc.) -- Jenkins
                // doesn't do host-level `ssh root@` prep in this repo's model, see that
                // script's header.
                // --server-side is a defensive choice, not a documented Longhorn requirement:
                // its 23 CRDs are the same shape of problem that made k8s/cnpg-operator.yaml
                // need this (large embedded schemas risk exceeding the 262144-byte
                // last-applied-configuration limit under plain client-side apply).
                sh "kubectl apply --server-side --force-conflicts -f k8s/longhorn.yaml"
            }
        }

        stage("Un-default Longhorn's built-in StorageClass") {
            steps {
                // local-path must stay the cluster's sole default. Longhorn's vendored
                // bundle creates its own "longhorn" StorageClass (3 replicas, no zone
                // anti-affinity override) from an embedded ConfigMap, marked default.
                // Patched off here every run (idempotent, self-healing) rather than
                // trusted to stay off, since upstream has open issues about this
                // annotation being reasserted on manager restart/upgrade
                // (longhorn/longhorn#3821, #9391).
                echo "Ensuring Longhorn's built-in StorageClass isn't marked default..."
                sh 'kubectl patch storageclass longhorn -p \'{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}\''
            }
        }

        stage('Apply Longhorn HA StorageClass') {
            steps {
                echo "Applying the longhorn-ha StorageClass (2 replicas, hard zone anti-affinity)"
                sh "kubectl apply -f k8s/longhorn-ha-storageclass.yaml"
            }
        }

        stage('Verify Deployment Status') {
            steps {
                echo "Verifying rollout status..."
                // Actively monitor the rollout to ensure it doesn't get stuck (e.g. on an ImagePullBackOff)
                sh "kubectl rollout status deployment/${DEPLOYMENT_NAME} --timeout=2m"
            }
        }
        stage('Prune Old Registry Tags') {
            steps {
                echo "Pruning ${IMAGE_NAME} tags in ${REGISTRY_DOMAIN}, keeping the ${RETAIN_COUNT} most recent numbered builds..."
                // Deletes old manifests via the registry HTTP API so the registry stops
                // serving them. This does NOT reclaim disk space -- the underlying blobs
                // stay on disk until `registry garbage-collect` runs (see
                // scripts/registry-gc.sh), so this is safe to run after every build.
                // "latest" and any non-numeric tag are never touched. Requires jq on the agent.
                sh '''
                    set -e
                    TAGS_JSON=$(curl -sf "https://${REGISTRY_DOMAIN}/v2/${IMAGE_NAME}/tags/list")
                    OLD_TAGS=$(echo "$TAGS_JSON" | jq -r '.tags[]?' | grep -E '^[0-9]+$' | sort -rn | tail -n +$((RETAIN_COUNT + 1)))

                    if [ -z "$OLD_TAGS" ]; then
                        echo "Nothing to prune."
                    fi

                    for TAG in $OLD_TAGS; do
                        DIGEST=$(curl -sI \
                            -H "Accept: application/vnd.docker.distribution.manifest.list.v2+json" \
                            -H "Accept: application/vnd.oci.image.index.v1+json" \
                            "https://${REGISTRY_DOMAIN}/v2/${IMAGE_NAME}/manifests/${TAG}" \
                            | grep -i '^docker-content-digest:' | tr -d '\\r' | awk '{print $2}')

                        if [ -n "$DIGEST" ]; then
                            echo "Deleting ${IMAGE_NAME}:${TAG} (${DIGEST})"
                            curl -sf -X DELETE "https://${REGISTRY_DOMAIN}/v2/${IMAGE_NAME}/manifests/${DIGEST}" || echo "Delete failed for ${TAG}, continuing"
                        else
                            echo "Could not resolve digest for tag ${TAG}, skipping"
                        fi
                    done
                '''
            }
        }
    }

    post {
        always {
            echo "Cleaning up local build workspace..."
            // Clean up old workspace files to prevent RHEL disk clutter
            cleanWs()
        }
        success {
            echo "Pipeline completed successfully! Build ${IMAGE_TAG} is now live."
        }
        failure {
            echo "Pipeline failed. Check build logs for details."
        }
    }
}
