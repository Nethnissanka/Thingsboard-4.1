pipeline {
    agent any

    parameters {
        string(name: 'TB_VERSION', defaultValue: '4.1', description: 'Enter the ThingsBoard version to upgrade (e.g., 4.2)')
    }

    environment {
        PACKAGE_REPO = "https://github.com/thingsboard/thingsboard/releases/download"
        DOCKER_COMPOSE_KAFKA = "docker-compose.kafka.yml"
        DOCKER_COMPOSE_TB = "docker-compose.qa.yml"
    }

    stages {
        stage('Checkout') {
            steps {
                echo '📥 Checking out QA repository...'
                checkout scm
            }
        }

        stage('Init Variables') {
            steps {
                script {
                    env.IMAGE_NAME = "thingsboard-qa:${params.TB_VERSION}"
                    env.NEW_CONTAINER_NAME = "thingsboard-qa-${params.TB_VERSION}"
                }
            }
        }

        stage('Detect Current Installed Version') {
            steps {
                script {
                    echo '🔍 Detecting current running ThingsBoard QA container...'
                    
                    def containerList = sh(script: "docker ps --format '{{.Names}}' | grep '^thingsboard-qa-' || true", returnStdout: true).trim()
                    
                    if (containerList) {
                        def currentContainer = containerList.split("\\n")[0].trim()
                        def currentImage = sh(script: "docker inspect ${currentContainer} --format '{{ index .Config.Image }}'", returnStdout: true).trim()
                        def currentTag = currentImage.split(":")[1]

                        echo "📦 Current running QA container: ${currentContainer}"
                        echo "📦 Current running QA image: ${currentImage}"
                        echo "📦 Current QA version: ${currentTag}"

                        env.CURRENT_CONTAINER_NAME = currentContainer
                        env.CURRENT_IMAGE_NAME = currentImage
                        env.CURRENT_VERSION = currentTag
                        env.ROLLBACK_IMAGE = "thingsboard-qa:rollback-${currentTag}"
                    } else {
                        echo "⚠️ No running ThingsBoard QA container found"
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
                    echo '🔍 Comparing current QA version with target version...'
                    if (!params.TB_VERSION) {
                        error '❌ Target TB_VERSION parameter is required!'
                    }
                    
                    echo "📦 Current QA version: ${env.CURRENT_VERSION ?: 'none'}, Target version: ${params.TB_VERSION}"
                    
                    if (env.CURRENT_VERSION == params.TB_VERSION) {
                        echo "✅ ThingsBoard QA is already running version ${env.CURRENT_VERSION}"
                        env.UPGRADE_REQUIRED = "false"
                    } else {
                        echo "⬆️ QA Upgrade required: ${env.CURRENT_VERSION ?: 'none'} ➜ ${params.TB_VERSION}"
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
                echo "✅ Skipping QA upgrade — Already running target version ${params.TB_VERSION}"
            }
        }

        stage('Download RPM') {
            when {
                expression { env.UPGRADE_REQUIRED == "true" }
            }
            steps {
                script {
                    echo "📥 Downloading ThingsBoard RPM package for QA..."
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
                echo "📦 Creating backup of current QA image: ${env.ROLLBACK_IMAGE}"
                sh "docker tag ${env.CURRENT_IMAGE_NAME} ${env.ROLLBACK_IMAGE}"
                echo "✅ QA backup image created: ${env.ROLLBACK_IMAGE}"
            }
        }

        stage('Build New Docker Image') {
            when {
                expression { env.UPGRADE_REQUIRED == "true" }
            }
            steps {
                echo "🔧 Building new ThingsBoard QA image: ${env.IMAGE_NAME}"
                sh """
                    docker build -t ${env.IMAGE_NAME} \
                        --build-arg TB_VERSION=${params.TB_VERSION} \
                        -f Dockerfile.qa .
                    
                    echo "✅ QA image built successfully: ${env.IMAGE_NAME}"
                    docker images | grep thingsboard-qa
                """
            }
        }

        stage('Generate Docker Compose') {
            when {
                expression { env.UPGRADE_REQUIRED == "true" }
            }
            steps {
                script {
                    echo "📝 Generating docker-compose file for ThingsBoard QA ${params.TB_VERSION}"
                    
                    def composeContent = """version: "3.8"
services:
  tb-server:
    image: thingsboard-qa:${params.TB_VERSION}
    container_name: thingsboard-qa-${params.TB_VERSION}
    ports:
      - "8081:8080"
    environment:
      - DATABASE_TS_TYPE=cassandra
      - SPRING_DATASOURCE_URL=jdbc:postgresql://10.160.0.2:5432/thingsboard_qa
      - SPRING_DATASOURCE_USERNAME=nethmi
      - SPRING_DATASOURCE_PASSWORD=123456
      - CASSANDRA_CLUSTER_NAME=ThingsBoard Cluster
      - CASSANDRA_KEYSPACE_NAME=thingsboard_qa
      - CASSANDRA_URL=10.160.0.2:9042
      - CASSANDRA_USE_CREDENTIALS=false
      - SECURITY_OAUTH2_ENABLED=false
      - TB_QUEUE_TYPE=kafka
      - TB_QUEUE_PREFIX=qa_
      - TB_KAFKA_SERVERS=kafka:9092
      - METRICS_ENABLE=true
      - METRICS_ENDPOINTS_EXPOSE=prometheus
    networks:
      - tb-kafka-net
    restart: no

networks:
  tb-kafka-net:
    external: true
"""
                    
                    writeFile file: env.DOCKER_COMPOSE_TB, text: composeContent
                    echo "✅ Generated QA compose file: ${env.DOCKER_COMPOSE_TB}"
                }
            }
        }

        stage('Stop Current ThingsBoard') {
            when {
                expression { env.UPGRADE_REQUIRED == "true" && env.CURRENT_CONTAINER_NAME != "" }
            }
            steps {
                echo "🛑 Stopping current ThingsBoard QA container: ${env.CURRENT_CONTAINER_NAME}"
                sh """
                    # Stop current ThingsBoard QA service (keep kafka running)
                    docker stop ${env.CURRENT_CONTAINER_NAME} || true
                    docker rm ${env.CURRENT_CONTAINER_NAME} || true
                    echo "✅ Old QA container stopped and removed"

                    echo "Stop running kafka container"
                    // docker stop kafka || true
                    // docker rm kafka || true

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
                echo "🚀 Deploying complete QA stack with ThingsBoard ${params.TB_VERSION}"
                sh """
                    # Deploy new QA version with both compose files
                    docker compose -f ${env.DOCKER_COMPOSE_TB} up -d tb-server-qa
                    
                    echo "✅ Complete QA stack deployed with ThingsBoard ${params.TB_VERSION}"
                    echo "🔍 Checking QA container status..."
                    docker ps | grep -E "(kafka|thingsboard-qa)"

                    echo "🔍 Waiting for QA services to be ready..."
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
                    echo "🔍 Verifying ThingsBoard QA deployment..."
                    echo "⏳ Waiting for ThingsBoard QA to start up..."
                    
                    // Wait for startup (ThingsBoard needs time to initialize)
                    sleep 60
                    
                    echo "🔍 Checking QA container health..."
                    sh "docker ps | grep thingsboard-qa-${params.TB_VERSION}"
                    
                    echo "🔍 Checking ThingsBoard QA logs for startup completion..."
                    sh """
                        # Show recent logs to verify startup
                        docker logs --tail 50 thingsboard-qa-${params.TB_VERSION} | grep -E "(Started ThingsBoard|Startup complete)" || true
                    """
                    
                    echo "🌐 Testing QA HTTP endpoint..."
                    // Test the QA web interface on port 8081
                    def maxRetries = 5
                    def retryCount = 0
                    def httpStatus = ""
                    
                    while (retryCount < maxRetries) {
                        try {
                            httpStatus = sh(script: "curl -s -o /dev/null -w '%{http_code}' http://localhost:8081/login", returnStdout: true).trim()
                            if (httpStatus == "200") {
                                echo "✅ ThingsBoard QA is responding correctly (HTTP 200)"
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
                        echo "❌ ThingsBoard QA is not responding correctly after ${maxRetries} attempts (HTTP ${httpStatus})"
                        error "❌ QA Deployment verification failed — HTTP status: ${httpStatus}"
                    }
                    
                    echo "🎉 QA Deployment verified successfully!"
                }
            }
        }
    }

    post {
        success {
            script {
                if (env.UPGRADE_REQUIRED == "true") {
                    echo """
🎉 ThingsBoard QA Upgrade Completed Successfully!
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ Upgraded from: ${env.CURRENT_VERSION ?: 'none'} → ${params.TB_VERSION}
🐳 QA Container: thingsboard-qa-${params.TB_VERSION}
🌐 QA Web UI: http://localhost:8081
📦 Backup available: ${env.ROLLBACK_IMAGE ?: 'none'}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                    """
                } else {
                    echo "✅ No QA upgrade needed. ThingsBoard QA ${params.TB_VERSION} is already running."
                }
            }
        }
        
        failure {
            script {
                echo "❌ ThingsBoard QA upgrade failed! Starting rollback procedures..."
                
                if (env.UPGRADE_REQUIRED == "true" && env.ROLLBACK_IMAGE && env.CURRENT_CONTAINER_NAME) {
                    try {
                        echo "🔄 Rolling back QA to previous version..."

                        sh """
                            # Stop failed QA deployment
                            docker compose -f ${env.DOCKER_COMPOSE_TB} down || true
                            
                            # Clean up any remaining containers
                            docker stop thingsboard-qa-${params.TB_VERSION} || true
                            docker rm thingsboard-qa-${params.TB_VERSION} || true
                            
                            # Restore previous QA version with Docker Compose approach
                            # First, create a rollback compose file
                            cat > docker-compose.rollback.qa.yml << 'EOF'
version: "3.8"
services:
  tb-server:
    image: ${env.ROLLBACK_IMAGE}
    container_name: ${env.CURRENT_CONTAINER_NAME}
    ports:
      - "8081:8080"
    environment:
      - DATABASE_TS_TYPE=cassandra
      - SPRING_DATASOURCE_URL=jdbc:postgresql://10.160.0.2:5432/thingsboard_qa
      - SPRING_DATASOURCE_USERNAME=nethmi
      - SPRING_DATASOURCE_PASSWORD=123456
      - CASSANDRA_CLUSTER_NAME=ThingsBoard Cluster
      - CASSANDRA_KEYSPACE_NAME=thingsboard_qa
      - CASSANDRA_URL=10.160.0.2:9042
      - CASSANDRA_USE_CREDENTIALS=false
      - SECURITY_OAUTH2_ENABLED=false
      - TB_QUEUE_TYPE=kafka
      - TB_QUEUE_PREFIX=qa_
      - TB_KAFKA_SERVERS=kafka:9092
      - METRICS_ENABLE=true
      - METRICS_ENDPOINTS_EXPOSE=prometheus
    networks:
      - tb-kafka-net
    restart: no

networks:
  tb-kafka-net:
    external: true
EOF
                            
                            # Deploy rollback stack for QA
                            docker compose -f docker-compose.rollback.qa.yml up -d
                        """

                        
                        echo "✅ QA Rollback completed successfully. ThingsBoard QA restored to v${env.CURRENT_VERSION}"
                    } catch (Exception e) {
                        echo "❌ QA Rollback failed: ${e.getMessage()}"
                        echo "⚠️ Manual intervention required for QA!"
                    }
                } else {
                    echo "⚠️ No QA backup available for rollback. Manual intervention required."
                }
                
                error "❌ ThingsBoard QA upgrade failed. Check logs for details."
            }
        }
        
        unstable {
            echo "⚠️ ThingsBoard QA upgrade completed but may be unstable. Monitor closely."
        }
        
        always {
            echo "🧹 Cleaning up QA temporary files..."
            sh """
                # Clean up downloaded RPM files
                #rm -f thingsboard-*.rpm || true
                
                # Clean up generated compose file
                #rm -f ${env.DOCKER_COMPOSE_TB} || true
                
                echo "✅ QA Cleanup completed"
            """
        }
    }
}
