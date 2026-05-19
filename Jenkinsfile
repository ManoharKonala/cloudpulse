pipeline {
    agent any

    environment {
        DOCKERHUB_USER = 'manohar122'
        IMAGE_PRODUCT  = "${DOCKERHUB_USER}/cloudpulse-product-service"
        IMAGE_ORDER    = "${DOCKERHUB_USER}/cloudpulse-order-service"
        IMAGE_FRONTEND = "${DOCKERHUB_USER}/cloudpulse-frontend"
        APP_SERVER_IP  = credentials('APP_SERVER_IP')
    }

    options {
        buildDiscarder(logRotator(numToKeepStr: '10'))
        timeout(time: 30, unit: 'MINUTES')
        timestamps()
    }

    stages {

        stage('Checkout') {
            steps {
                echo "Cloning repository — build #${BUILD_NUMBER}"
                checkout scm
            }
        }

        // ── FIX 1: Bootstrap pip if it is not present on the Jenkins agent ──────
        stage('Lint & Test') {
            parallel {
                stage('Test — Product Service') {
                    steps {
                        dir('services/product-service') {
                            sh '''
                                # Ensure pip is available; install it if missing
                                python3 -m ensurepip --upgrade 2>/dev/null || \
                                    curl -sSL https://bootstrap.pypa.io/get-pip.py | python3

                                python3 -m pip install --quiet --upgrade pip
                                python3 -m pip install --quiet -r requirements.txt
                                python3 -m py_compile app.py
                                echo "Syntax OK: product-service"
                            '''
                        }
                    }
                }
                stage('Test — Order Service') {
                    steps {
                        dir('services/order-service') {
                            sh '''
                                # Ensure pip is available; install it if missing
                                python3 -m ensurepip --upgrade 2>/dev/null || \
                                    curl -sSL https://bootstrap.pypa.io/get-pip.py | python3

                                python3 -m pip install --quiet --upgrade pip
                                python3 -m pip install --quiet -r requirements.txt
                                python3 -m py_compile app.py
                                echo "Syntax OK: order-service"
                            '''
                        }
                    }
                }
            }
        }

        // ── FIX 2: Verify Docker is reachable before any docker commands ─────────
        stage('Prepare Docker') {
            steps {
                sh '''
                    # Make the socket accessible to the jenkins user
                    sudo chmod 666 /var/run/docker.sock

                    # Confirm docker CLI is on PATH (fails fast with a clear message)
                    if ! command -v docker >/dev/null 2>&1; then
                        echo "ERROR: docker CLI not found on PATH. Add the Docker socket"
                        echo "volume AND the docker binary to the Jenkins container, e.g.:"
                        echo "  -v /usr/bin/docker:/usr/bin/docker"
                        echo "  -v /var/run/docker.sock:/var/run/docker.sock"
                        exit 1
                    fi

                    docker version
                '''
            }
        }

        stage('Build Docker Images') {
            parallel {
                stage('Build Product Service') {
                    steps {
                        sh "docker build -t ${IMAGE_PRODUCT}:${BUILD_NUMBER} -t ${IMAGE_PRODUCT}:latest ./services/product-service"
                    }
                }
                stage('Build Order Service') {
                    steps {
                        sh "docker build -t ${IMAGE_ORDER}:${BUILD_NUMBER} -t ${IMAGE_ORDER}:latest ./services/order-service"
                    }
                }
                stage('Build Frontend') {
                    steps {
                        sh "docker build -t ${IMAGE_FRONTEND}:${BUILD_NUMBER} -t ${IMAGE_FRONTEND}:latest ./services/frontend"
                    }
                }
            }
        }

        stage('Push to DockerHub') {
            steps {
                withCredentials([usernamePassword(
                    credentialsId: 'dockerhub-credentials',
                    usernameVariable: 'DOCKER_USER',
                    passwordVariable: 'DOCKER_PASS'
                )]) {
                    sh '''
                        echo "$DOCKER_PASS" | docker login -u "$DOCKER_USER" --password-stdin
                        docker push ${IMAGE_PRODUCT}:${BUILD_NUMBER}
                        docker push ${IMAGE_PRODUCT}:latest
                        docker push ${IMAGE_ORDER}:${BUILD_NUMBER}
                        docker push ${IMAGE_ORDER}:latest
                        docker push ${IMAGE_FRONTEND}:${BUILD_NUMBER}
                        docker push ${IMAGE_FRONTEND}:latest
                    '''
                }
            }
        }

        stage('Deploy to AWS EC2') {
            steps {
                withCredentials([sshUserPrivateKey(credentialsId: 'APP_SERVER_SSH_KEY', keyFileVariable: 'SSH_KEY')]) {
                    sh '''
                        ssh -i $SSH_KEY -o StrictHostKeyChecking=no ubuntu@${APP_SERVER_IP} "
                            cd /opt/cloudpulse &&
                            git pull origin main &&
                            DOCKERHUB_USER=${DOCKERHUB_USER} docker-compose -f docker-compose.prod.yml pull &&
                            DOCKERHUB_USER=${DOCKERHUB_USER} docker-compose -f docker-compose.prod.yml up -d --remove-orphans
                        "
                    '''
                }
            }
        }

        stage('Health Check') {
            steps {
                sh '''
                    echo "Waiting for services to start..."
                    sleep 20
                    curl --fail --retry 5 --retry-delay 5 \
                         http://${APP_SERVER_IP}/api/health/products \
                      || (echo "product-service health check FAILED" && exit 1)
                    curl --fail --retry 5 --retry-delay 5 \
                         http://${APP_SERVER_IP}/api/health/orders \
                      || (echo "order-service health check FAILED" && exit 1)
                    echo "All services healthy. Build #${BUILD_NUMBER} is live at http://${APP_SERVER_IP}"
                '''
            }
        }

    }

    post {
        success {
            echo "Pipeline SUCCESS — Build #${BUILD_NUMBER} deployed to http://${APP_SERVER_IP}"
        }
        failure {
            echo "Pipeline FAILED at stage: ${STAGE_NAME}. Check logs above."
        }
        always {
            // FIX 3: || true already present — also guard with command -v so the
            // post block never fails when docker CLI is absent on the agent
            sh 'command -v docker >/dev/null 2>&1 && docker logout || true'
        }
    }
}
