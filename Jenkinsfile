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
                echo "Applying manifests and updating deployment image..."
                // Always apply the manifests first so Service or ConfigMap changes take effect
                sh "kubectl apply -f deployment.yaml"
                // Then update the image to the exact build tag
                sh "kubectl set image deployment/${DEPLOYMENT_NAME} app-container=${REGISTRY_DOMAIN}/${IMAGE_NAME}:${IMAGE_TAG}"
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
