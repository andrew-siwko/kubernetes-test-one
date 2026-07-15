pipeline {
    agent { label 'docker-builder' }

    environment {
        // Use the domain name your K8s cluster uses to resolve the registry
        REGISTRY_DOMAIN = 'kregistry.siwko.org:5000'
        IMAGE_NAME      = 'my-app'
        IMAGE_TAG       = "${env.BUILD_NUMBER}"
        DEPLOYMENT_NAME = 'my-app-deployment'
    }

    stages {
        stage('Checkout Code') {
            steps {
                // Jenkins automatically pulls the code from Git here
                checkout scm
            }
        }

        stage('Build Docker Image') {
            steps {
                echo "Building image: ${REGISTRY_DOMAIN}/${IMAGE_NAME}:${IMAGE_TAG}..."
                // Build the image locally on the RHEL 10 agent
                sh "docker build -t ${REGISTRY_DOMAIN}/${IMAGE_NAME}:${IMAGE_TAG} ."
                sh "docker tag ${REGISTRY_DOMAIN}/${IMAGE_NAME}:${IMAGE_TAG} ${REGISTRY_DOMAIN}/${IMAGE_NAME}:latest"
            }
        }

        stage('Push to Local Registry') {
            steps {
                echo "Pushing images to local registry..."
                // Since this agent runs on the registry host, we push directly to localhost
                // without encountering external TLS or network routing issues
                sh "docker push ${REGISTRY_DOMAIN}/${IMAGE_NAME}:${IMAGE_TAG}"
                sh "docker push ${REGISTRY_DOMAIN}/${IMAGE_NAME}:latest"
            }
        }

        stage('Deploy to Kubernetes') {
            steps {
                echo "Updating Kubernetes deployment..."
                // Safely update the container image in your deployment.
                // If the deployment doesn't exist yet, it will apply your manifest first.
                sh """
                    if kubectl get deployment ${DEPLOYMENT_NAME} >/dev/null 2>&1; then
                        kubectl set image deployment/${DEPLOYMENT_NAME} app-container=${REGISTRY_DOMAIN}/${IMAGE_NAME}:${IMAGE_TAG} --record
                    else
                        # If bootstrapping for the first time, apply your k8s deployment manifest
                        kubectl apply -f k8s/deployment.yaml
                        kubectl set image deployment/${DEPLOYMENT_NAME} app-container=${REGISTRY_DOMAIN}/${IMAGE_NAME}:${IMAGE_TAG}
                    fi
                """
            }
        }

        stage('Verify Deployment Status') {
            steps {
                echo "Verifying rollout status..."
                // Actively monitor the rollout to ensure it doesn't get stuck (e.g. on an ImagePullBackOff)
                sh "kubectl rollout status deployment/${DEPLOYMENT_NAME} --timeout=2m"
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
