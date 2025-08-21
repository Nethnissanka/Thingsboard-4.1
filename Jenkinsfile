pipeline {
    agent any

    parameters {
        string(name: 'TB_VERSION', defaultValue: '4.2', description: 'Enter the ThingsBoard version to upgrade (e.g., 4.2)')
    }

    environment {
        PACKAGE_REPO = "https://github.com/thingsboard/thingsboard/releases/download"
        DOCKER_COMPOSE_KAFKA = "docker-compose.kafka.yml"
        DOCKER_COMPOSE_TB = "docker-compose.thingsboard.yml"
    }

    stages {
        stage('Checkout') {
            steps {
                echo '📥 Checking out repository...'
                checkout scm
            }
        }

        stage('Init Variables') {
            steps {
                script {
                    env.IMAGE_NAME = "thingsboard:${params.TB_VERSION}"
                    env.NEW_CONTAINER_NAME = "thingsboard-${params.TB_VERSION}"
                }
            }
        }

        stage('Detect Current Installed Version') {
            steps {
                script {
                    echo '🔍 Detecting current running ThingsBoard container...'
                    
                    def containerList = sh(script: "docker ps --format '{{.Names}}' | grep '^thingsboard-' || true", returnStdout: true).trim()
                    
                    if (containerList) {
                        def currentContainer = containerList.split("\\n")[0].trim()
                        def currentImage = sh(script: "docker inspect ${currentContainer} --format '{{ index .Config.Image }}'", returnStdout: true).trim()
                        def currentTag = currentImage.split(":")[1]

                        echo "📦 Current running container: ${currentContainer}"
                        echo "📦 Current running image: ${currentImage}"
                        echo "📦 Current version: ${currentTag}"

                        env.CURRENT_CONTAINER_NAME = currentContainer
                        env.CURRENT_IMAGE_NAME = currentImage
                        env.CURRENT_VERSION = currentTag
                        env.ROLLBACK_IMAGE = "thingsboard:rollback-${currentTag}"
                    } else {
                        echo "⚠️ No running ThingsBoard container found"
                        env.CURRENT_CONTAINER_NAME = ""
                        env.CURRENT_VERSION = "none"
                        env.CURRENT_IMAGE_NAME = ""
                        env.ROLLBACK_IMAGE = ""
                    }
                }
            }
        }

        stage('Compare Versions') {
            steps {
                script {
                    echo '🔍 Comparing current version with target version...'
                    if (!params.TB_VERSION) {
                        error '❌ Target TB_VERSION parameter is required!'
                    }
                    
                    echo "📦 Current version: ${env.CURRENT_VERSION ?: 'none'}, Target version: ${params.TB_VERSION}"
                    
                    if (env.CURRENT_VERSION == params.TB_VERSION) {
                        echo "✅ ThingsBoard is already running version ${env.CURRENT_VERSION}"
                        env.UPGRADE_REQUIRED = "false"
                    } else {
                        echo "⬆️ Upgrade required: ${env.CURRENT_VERSION ?: 'none'} ➜ ${params.TB_VERSION}"
                        env.UPGRADE_REQUIRED = "true"
                    }
                }
            }
        }

        stage('Skip Upgrade') {
            when {
                expression { env.UPGRADE_REQUIRED == "false" }
            }
            steps {
                echo "✅ Skipping upgrade — Already running target version ${params.TB_VERSION}"
            }
        }

        stage('Download RPM') {
            when {
                expression { env.UPGRADE_REQUIRED == "true" }
            }
            steps {
                script {
                    echo "📥 Downloading ThingsBoard RPM package..."
                    def rpmUrl = "${PACKAGE_REPO}/v${params.TB_VERSION}/thingsboard-${params.TB_VERSION}.rpm"
                    echo "📥 Downloading RPM from: ${rpmUrl}"
                    
                    sh """
                        # Download the RPM package
                        curl -L -o thingsboard-${params.TB_VERSION}.rpm ${rpmUrl}
                        ls -lh thingsboard-*.rpm
                    
                        # Prepare application directory structure
                        mkdir -p application/target
                        cp thingsboard-${params.TB_VERSION}.rpm application/target/thingsboard.rpm
                        
                        echo "✅ RPM downloaded and copied to application/target/"
                    """
                }
            }
        }

        stage('Backup Current Image') {
            when {
                expression { env.UPGRADE_REQUIRED == "true" && env.CURRENT_IMAGE_NAME != "" }
            }
            steps {
                echo "📦 Creating backup of current image: ${env.ROLLBACK_IMAGE}"
                sh "docker tag ${env.CURRENT_IMAGE_NAME} ${env.ROLLBACK_IMAGE}"
                echo "✅ Backup image created: ${env.ROLLBACK_IMAGE}"
            }
        }

        stage('Build New Docker Image') {
            when {
                expression { env.UPGRADE_REQUIRED == "true" }
            }
            steps {
                echo "🔧 Building new ThingsBoard image: ${env.IMAGE_NAME}"
                sh """
                    docker build -t ${env.IMAGE_NAME} \
                        --build-arg TB_VERSION=${params.TB_VERSION} \
                        -f Dockerfile .
                    
                    echo "✅ Image built successfully: ${env.IMAGE_NAME}"
                    docker images | grep thingsboard
                """
            }
        }

        stage('Generate Docker Compose') {
            when {
                expression { env.UPGRADE_REQUIRED == "true" }
            }
            steps {
                script {
                    echo "📝 Generating docker-compose file for ThingsBoard ${params.TB_VERSION}"
                    
                    def composeContent = """version: "3.8"
services:
  tb-server:
    image: thingsboard:${params.TB_VERSION}
    container_name: thingsboard-${params.TB_VERSION}
    ports:
      - "8080:8080"
    environment:
      - DATABASE_TS_TYPE=cassandra
      - SPRING_DATASOURCE_URL=jdbc:postgresql://10.160.0.2:5432/thingsboard_restore
      - SPRING_DATASOURCE_USERNAME=nethmi
      - SPRING_DATASOURCE_PASSWORD=123456
      - CASSANDRA_CLUSTER_NAME=ThingsBoard Cluster
      - CASSANDRA_KEYSPACE_NAME=thingsboard
      - CASSANDRA_URL=10.160.0.2:9042
      - CASSANDRA_USE_CREDENTIALS=false
      - SECURITY_OAUTH2_ENABLED=false
      - TB_QUEUE_TYPE=kafka
      - TB_QUEUE_PREFIX=dev_
      - TB_KAFKA_SERVERS=kafka:9092
      - METRICS_ENABLE=true
      - METRICS_ENDPOINTS_EXPOSE=prometheus
    depends_on:
      - kafka
    networks:
      - tb-kafka-net
    restart: no

networks:
  tb-kafka-net:
    external: true
"""
                    
                    writeFile file: env.DOCKER_COMPOSE_TB, text: composeContent
                    echo "✅ Generated: ${env.DOCKER_COMPOSE_TB}"
                }
            }
        }

        stage('Stop Current ThingsBoard') {
            when {
                expression { env.UPGRADE_REQUIRED == "true" && env.CURRENT_CONTAINER_NAME != "" }
            }
            steps {
                echo "🛑 Stopping current ThingsBoard container: ${env.CURRENT_CONTAINER_NAME}"
                sh """
                    # Stop current ThingsBoard service (keep kafka running)
                    docker stop ${env.CURRENT_CONTAINER_NAME} || true
                    docker rm ${env.CURRENT_CONTAINER_NAME} || true
                    echo "✅ Old container stopped and removed"
                    echo "Stop running kafka container"
                    docker stop kafka || true
                    docker rm kafka || true
                    echo "🔍 Verifying no conflicting containers..."
                    docker ps -a | grep -E "(kafka|thingsboard)" || echo "No conflicting containers found"
                """
            }
        }

        stage('Deploy New Version') {
            when {
                expression { env.UPGRADE_REQUIRED == "true" }
            }
            steps {
                echo "🚀 Deploying complete stack with ThingsBoard ${params.TB_VERSION}"
                sh """
                    # Deploy new version with both compose files
                    docker compose -f ${env.DOCKER_COMPOSE_KAFKA} -f ${env.DOCKER_COMPOSE_TB} up -d tb-server
                    
                    echo "✅ Complete stack deployed with ThingsBoard ${params.TB_VERSION}"
                    echo "🔍 Checking container status..."
                    # docker ps | grep thingsboard || true
                    docker ps | grep -E "(kafka|thingsboard)"

                    echo "🔍 Waiting for services to be ready..."
                    sleep 10

                """
            }
        }

        stage('Verify Deployment') {
            when {
                expression { env.UPGRADE_REQUIRED == "true" }
            }
            steps {
                script {
                    echo "🔍 Verifying ThingsBoard deployment..."
                    echo "⏳ Waiting for ThingsBoard to start up..."
                    
                    // Wait for startup (ThingsBoard needs time to initialize)
                    sleep 60
                    
                    echo "🔍 Checking container health..."
                    sh "docker ps | grep thingsboard-${params.TB_VERSION}"
                    
                    echo "🔍 Checking ThingsBoard logs for startup completion..."
                    sh """
                        # Show recent logs to verify startup
                        docker logs --tail 50 thingsboard-${params.TB_VERSION} | grep -E "(Started ThingsBoard|Startup complete)" || true
                    """
                    
                    echo "🌐 Testing HTTP endpoint..."
                    // Test the web interface
                    def maxRetries = 5
                    def retryCount = 0
                    def httpStatus = ""
                    
                    while (retryCount < maxRetries) {
                        try {
                            httpStatus = sh(script: "curl -s -o /dev/null -w '%{http_code}' http://localhost:8080/login", returnStdout: true).trim()
                            if (httpStatus == "200") {
                                echo "✅ ThingsBoard is responding correctly (HTTP 200)"
                                break
                            }
                        } catch (Exception e) {
                            echo "⏳ Attempt ${retryCount + 1}/${maxRetries}: HTTP status ${httpStatus}, retrying in 30 seconds..."
                        }
                        
                        retryCount++
                        if (retryCount < maxRetries) {
                            sleep 30
                        }
                    }
                    
                    if (httpStatus != "200") {
                        echo "❌ ThingsBoard is not responding correctly after ${maxRetries} attempts (HTTP ${httpStatus})"
                        error "❌ Deployment verification failed — HTTP status: ${httpStatus}"
                    }
                    
                    echo "🎉 Deployment verified successfully!"
                }
            }
        }
    }

    post {
        success {
            script {
                if (env.UPGRADE_REQUIRED == "true") {
                    echo """
🎉 ThingsBoard Upgrade Completed Successfully!
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ Upgraded from: ${env.CURRENT_VERSION ?: 'none'} → ${params.TB_VERSION}
🐳 Container: thingsboard-${params.TB_VERSION}
🌐 Web UI: http://localhost:8080
📦 Backup available: ${env.ROLLBACK_IMAGE ?: 'none'}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                    """
                } else {
                    echo "✅ No upgrade needed. ThingsBoard ${params.TB_VERSION} is already running."
                }
            }
        }
        
        failure {
            script {
                echo "❌ ThingsBoard upgrade failed! Starting rollback procedures..."
                
                if (env.UPGRADE_REQUIRED == "true" && env.ROLLBACK_IMAGE && env.CURRENT_CONTAINER_NAME) {
                    try {
                        echo "🔄 Rolling back to previous version..."
                        // sh """
                        //     # Stop failed container
                        //     docker stop thingsboard-${params.TB_VERSION} || true
                        //     docker rm thingsboard-${params.TB_VERSION} || true
                            
                        //     # Restore previous version
                        //     docker run -d --name ${env.CURRENT_CONTAINER_NAME} \
                        //         --network tb-kafka-net \
                        //         -p 8080:8080 \
                        //         -e DATABASE_TS_TYPE=cassandra \
                        //         -e SPRING_DATASOURCE_URL=jdbc:postgresql://10.160.0.2:5432/thingsboard_restore \
                        //         -e SPRING_DATASOURCE_USERNAME=nethmi \
                        //         -e SPRING_DATASOURCE_PASSWORD=123456 \
                        //         -e CASSANDRA_CLUSTER_NAME="ThingsBoard Cluster" \
                        //         -e CASSANDRA_KEYSPACE_NAME=thingsboard \
                        //         -e CASSANDRA_URL=10.160.0.2:9042 \
                        //         -e CASSANDRA_USE_CREDENTIALS=false \
                        //         -e SECURITY_OAUTH2_ENABLED=false \
                        //         -e TB_QUEUE_TYPE=kafka \
                        //         -e TB_QUEUE_PREFIX=dev_ \
                        //         -e TB_KAFKA_SERVERS=kafka:9092 \
                        //         -e METRICS_ENABLE=true \
                        //         -e METRICS_ENDPOINTS_EXPOSE=prometheus \
                        //         ${env.ROLLBACK_IMAGE}
                        // """

                        sh """
                            # Stop failed deployment
                            docker compose -f ${env.DOCKER_COMPOSE_KAFKA} -f ${env.DOCKER_COMPOSE_TB} down || true
                            
                            # Clean up any remaining containers
                            docker stop thingsboard-${params.TB_VERSION} kafka || true
                            docker rm thingsboard-${params.TB_VERSION} kafka || true
                            
                            # Restore previous version with Docker Compose approach
                            # First, create a rollback compose file
                            cat > docker-compose.rollback.yml << 'EOF'
version: "3.8"
services:
  tb-server:
    image: ${env.ROLLBACK_IMAGE}
    container_name: ${env.CURRENT_CONTAINER_NAME}
    ports:
      - "8080:8080"
    environment:
      - DATABASE_TS_TYPE=cassandra
      - SPRING_DATASOURCE_URL=jdbc:postgresql://10.160.0.2:5432/thingsboard_restore
      - SPRING_DATASOURCE_USERNAME=nethmi
      - SPRING_DATASOURCE_PASSWORD=123456
      - CASSANDRA_CLUSTER_NAME=ThingsBoard Cluster
      - CASSANDRA_KEYSPACE_NAME=thingsboard
      - CASSANDRA_URL=10.160.0.2:9042
      - CASSANDRA_USE_CREDENTIALS=false
      - SECURITY_OAUTH2_ENABLED=false
      - TB_QUEUE_TYPE=kafka
      - TB_QUEUE_PREFIX=dev_
      - TB_KAFKA_SERVERS=kafka:9092
      - METRICS_ENABLE=true
      - METRICS_ENDPOINTS_EXPOSE=prometheus
    depends_on:
      - kafka
    networks:
      - tb-kafka-net
    restart: no

networks:
  tb-kafka-net:
    external: true
EOF
                            
                            # Deploy rollback stack
                            docker compose -f ${env.DOCKER_COMPOSE_KAFKA} -f docker-compose.rollback.yml up -d
                            
                            # Clean up rollback file
                            #rm -f docker-compose.rollback.yml
                        """

                        
                        echo "✅ Rollback completed successfully. ThingsBoard restored to v${env.CURRENT_VERSION}"
                    } catch (Exception e) {
                        echo "❌ Rollback failed: ${e.getMessage()}"
                        echo "⚠️ Manual intervention required!"
                    }
                } else {
                    echo "⚠️ No backup available for rollback. Manual intervention required."
                }
                
                error "❌ ThingsBoard upgrade failed. Check logs for details."
            }
        }
        
        unstable {
            echo "⚠️ ThingsBoard upgrade completed but may be unstable. Monitor closely."
        }
        
        always {
            echo "🧹 Cleaning up temporary files..."
            sh """
                # Clean up downloaded RPM files
                #rm -f thingsboard-*.rpm || true
                
                # Clean up generated compose file
                #rm -f ${env.DOCKER_COMPOSE_TB} || true
                
                echo "✅ Cleanup completed"
            """
        }
    }
}
