pipeline {
    agent any

    parameters {
        string(name: 'TB_VERSION', defaultValue: '4.2.0', description: 'Enter the ThingsBoard version to upgrade (e.g., 4.2.0)')
    }

    environment {
        PACKAGE_REPO  = "https://github.com/thingsboard/thingsboard/releases/download"
        KAFKA_COMPOSE_FILE = "docker-compose.kafka.yml"
        TB_COMPOSE_FILE = "docker-compose.yml"
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
                    if (!env.CURRENT_VERSION || env.CURRENT_VERSION == "none") {
                        echo "⚠️ No current version detected, proceeding with fresh installation"
                        env.UPGRADE_REQUIRED = "true"
                    } else if (env.CURRENT_VERSION == params.TB_VERSION) {
                        echo "✅ ThingsBoard is already up to date (v${env.CURRENT_VERSION})"
                        env.UPGRADE_REQUIRED = "false"
                    } else {
                        echo "⬆️ Upgrade required: ${env.CURRENT_VERSION} ➜ ${env.TB_VERSION}"
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
                echo "✅ Skipping upgrade — Already latest version."
            }
        }
        
        stage('Download RPM') {
            when {
                expression { env.UPGRADE_REQUIRED == "true" }
            }
            steps {
                script {
                    echo "📥 Downloading ThingsBoard RPM package..."
                    def rpmUrl = "${PACKAGE_REPO}/v${env.TB_VERSION}/thingsboard-${env.TB_VERSION}.rpm"
                    echo "📥 Downloading RPM from: ${rpmUrl}"
                    
                    // Fixed the shell script syntax - using triple double quotes for proper interpolation
                    sh """
                        # Clean up any existing RPM files
                        rm -f thingsboard-*.rpm
                        
                        # Download the new RPM
                        curl -L -o thingsboard-${env.TB_VERSION}.rpm ${rpmUrl}
                        
                        # Verify download was successful
                        if [ ! -f "thingsboard-${env.TB_VERSION}.rpm" ]; then
                            echo "❌ RPM download failed!"
                            exit 1
                        fi
                        
                        # Prepare directory structure
                        mkdir -p application/target
                        
                        # Copy RPM to target location
                        cp thingsboard-${env.TB_VERSION}.rpm application/target/thingsboard.rpm
                        
                        echo "✅ RPM downloaded successfully: \$(ls -lh thingsboard-${env.TB_VERSION}.rpm)"
                    """
                }
            }
        }

        stage('Backup Current Image') {
            when {
                expression { env.UPGRADE_REQUIRED == "true" && env.CURRENT_IMAGE_NAME != "" }
            }
            steps {
                echo "📦 Tagging current image for rollback: ${env.ROLLBACK_IMAGE}"
                sh "docker tag ${env.CURRENT_IMAGE_NAME} ${env.ROLLBACK_IMAGE}"
            }
        }

        stage('Build New Docker Image') {
            when {
                expression { env.UPGRADE_REQUIRED == "true" }
            }
            steps {
                echo "🔧 Building image ${IMAGE_NAME}"
                sh "docker build -t ${IMAGE_NAME} ."
            }
        }

        stage('Update Docker Compose') {
            when {
                expression { env.UPGRADE_REQUIRED == "true" }
            }
            steps {
                script {
                    echo "📝 Updating docker-compose.yml with new image version"
                    
                    // Read the current docker-compose file
                    def composeContent = readFile(file: 'docker-compose.yml')
                    
                    // Update the image version
                    def updatedContent = composeContent.replaceAll(
                        /image: thingsboard:.*/, 
                        "image: thingsboard:${params.TB_VERSION}"
                    )
                    
                    // Write the updated content back
                    writeFile(file: 'docker-compose.yml', text: updatedContent)
                    
                    echo "✅ Docker compose file updated successfully"
                }
            }
        }

        stage('Stop and Remove Old Container') {
            when {
                expression { env.UPGRADE_REQUIRED == "true" && env.CURRENT_CONTAINER_NAME != "" }
            }
            steps {
                echo "🛑 Stopping container ${env.CURRENT_CONTAINER_NAME}"
                sh """
                    docker stop ${env.CURRENT_CONTAINER_NAME} || true
                    docker rm ${env.CURRENT_CONTAINER_NAME} || true
                """
            }
        }

        stage('Start New Version with Docker Compose') {
            when {
                expression { env.UPGRADE_REQUIRED == "true" }
            }
            steps {
                echo "🚀 Launching version ${params.TB_VERSION} using docker compose"
                sh """
                    # Start both Kafka and ThingsBoard services
                    docker compose -f ${KAFKA_COMPOSE_FILE} -f ${TB_COMPOSE_FILE} up -d
                """
            }
        }

        stage('Wait for Startup') {
            when {
                expression { env.UPGRADE_REQUIRED == "true" }
            }
            steps {
                echo "⏳ Waiting for ThingsBoard to start up (60 seconds)..."
                sleep 60
            }
        }

        stage('Verify Deployment') {
            when {
                expression { env.UPGRADE_REQUIRED == "true" }
            }
            steps {
                script {
                    echo "🔍 Verifying ThingsBoard deployment"
                    
                    // Check if container is running
                    def isRunning = sh(script: "docker inspect -f '{{.State.Running}}' ${env.NEW_CONTAINER_NAME}", returnStdout: true).trim()
                    if (isRunning != "true") {
                        error "❌ Container ${env.NEW_CONTAINER_NAME} is not running"
                    }
                    
                    // Check container logs for successful startup
                    def logs = sh(script: "docker logs ${env.NEW_CONTAINER_NAME} --tail 50", returnStdout: true).trim()
                    if (!logs.contains("Started ThingsBoard")) {
                        echo "⚠️ ThingsBoard startup not complete yet, waiting additional 30 seconds..."
                        sleep 30
                        logs = sh(script: "docker logs ${env.NEW_CONTAINER_NAME} --tail 50", returnStdout: true).trim()
                    }
                    
                    // Check for version in logs
                    if (!logs.contains("ThingsBoard v${params.TB_VERSION}")) {
                        error "❌ Wrong version detected in logs"
                    }
                    
                    // Check HTTP response
                    echo "🔍 Checking HTTP response..."
                    def maxRetries = 10
                    def retryCount = 0
                    def success = false
                    
                    while (retryCount < maxRetries && !success) {
                        try {
                            def code = sh(script: "curl -s -o /dev/null -w '%{http_code}' http://localhost:8080/login || echo '000'", returnStdout: true).trim()
                            if (code == "200") {
                                success = true
                                echo "✅ ThingsBoard is up and responding (HTTP 200)"
                            } else {
                                echo "⏳ Waiting for ThingsBoard to respond (HTTP ${code}), retry ${retryCount + 1}/${maxRetries}"
                                sleep 10
                                retryCount++
                            }
                        } catch (Exception e) {
                            echo "⏳ Connection failed, retry ${retryCount + 1}/${maxRetries}"
                            sleep 10
                            retryCount++
                        }
                    }
                    
                    if (!success) {
                        error "❌ ThingsBoard did not become responsive within expected time"
                    }
                }
            }
        }
    }

    post {
        success {
            script {
                echo "✅ Upgrade pipeline completed successfully!"
                if (env.UPGRADE_REQUIRED == "true") {
                    echo "🎉 ThingsBoard upgraded from v${env.CURRENT_VERSION} to v${env.TB_VERSION} successfully!"
                    
                    // Clean up old image if upgrade was successful
                    if (env.CURRENT_IMAGE_NAME && env.CURRENT_IMAGE_NAME != "") {
                        echo "🧹 Cleaning up old image: ${env.CURRENT_IMAGE_NAME}"
                        sh "docker rmi ${env.CURRENT_IMAGE_NAME} || true"
                    }
                } else {
                    echo "✅ No upgrade needed. Still running v${env.CURRENT_VERSION}."
                }
            }
        }
        failure {
            script {
                echo "❌ Upgrade failed. Starting rollback..."
                
                if (env.ROLLBACK_IMAGE && env.ROLLBACK_IMAGE != "") {
                    echo "🔁 Restoring from backup image: ${env.ROLLBACK_IMAGE}"
                    
                    // Stop new container if it exists
                    sh """
                        docker stop ${env.NEW_CONTAINER_NAME} || true
                        docker rm ${env.NEW_CONTAINER_NAME} || true
                    """
                    
                    // Revert docker-compose to previous version
                    if (env.CURRENT_VERSION && env.CURRENT_VERSION != "none") {
                        def composeContent = readFile(file: 'docker-compose.yml')
                        def revertedContent = composeContent.replaceAll(
                            /image: thingsboard:.*/, 
                            "image: thingsboard:${env.CURRENT_VERSION}"
                        )
                        writeFile(file: 'docker-compose.yml', text: revertedContent)
                    }
                    
                    // Start previous version
                    sh """
                        docker compose -f ${KAFKA_COMPOSE_FILE} -f ${TB_COMPOSE_FILE} up -d
                    """
                    
                    echo "✅ Rollback complete. ThingsBoard is back to v${env.CURRENT_VERSION}"
                } else {
                    echo "⚠️ No backup image available for rollback."
                }
                
                error "❌ Upgrade failed. Rollback was attempted."
            }
        }
        
        unstable {
            echo "⚠️ ThingsBoard upgrade is unstable!"
        }
    }
}
