pipeline{
    agent any
     environment {
        DOCKER_USER = "kevinjcloud"

        FRONTEND_IMAGE = "${DOCKER_USER}/wanderblog-frontend"
        BACKEND_IMAGE  = "${DOCKER_USER}/wanderblog-backend"

    }
     parameters {
        string(
            name: 'FRONTEND_DOCKER_TAG',
            defaultValue: '',
            description: 'Docker image tag for frontend'
        )

        string(
            name: 'BACKEND_DOCKER_TAG',
            defaultValue: '',
            description: 'Docker image tag for backend'
        )
    }
    stages{
         stage("Validate Parameters") {
            steps {
                script {
                    if (!params.FRONTEND_DOCKER_TAG?.trim() ||
                        !params.BACKEND_DOCKER_TAG?.trim()) {

                        error("FRONTEND_DOCKER_TAG and BACKEND_DOCKER_TAG must be provided.")
                    }
                }
            }
        }

        stage("Workspace cleanup"){
            steps{
               script{
                cleanWs()
               }
            }
        }
    
    
        stage("Git Checkout"){
            steps{
               script{
                checkout scmGit(
                    branches: [[name: '*/main']],
                    extensions: [],
                    userRemoteConfigs: [[
                        credentialsId: 'git-token',
                        url: 'https://github.com/KevinJCloud/Wanderblog.git'
                    ]])

               }
            }
        }
        
   
        stage("SonarCloud Analysis") {
            steps {
               script {
                 def scannerHome = tool 'sonarqube-scanner'

                 withSonarQubeEnv("sonar-qube") {
                 sh """
                  ${scannerHome}/bin/sonar-scanner \
                   -Dsonar.projectName=wanderblog \
                   -Dsonar.projectKey=wanderblog \
                   -Dsonar.organization=wanderblog \
                   -X
                     """
                    }
                 }
            }
        }
    
   
        stage("Docker: Build Images") {
            steps {
                script {

                    withCredentials([
                        usernamePassword(
                            credentialsId: 'dockerlogin',
                            usernameVariable: 'Dockerhub_user',
                            passwordVariable: 'Dockerhub_pass'
                        )
                    ]) {

                        dir('server') {
                            sh """
                                docker build \
                                -t ${BACKEND_IMAGE}:${params.BACKEND_DOCKER_TAG} .
                            """

                            sh """
                                trivy image \
                                ${BACKEND_IMAGE}:${params.BACKEND_DOCKER_TAG}
                            """
                        }

                        dir('frontend') {
                            sh """
                                docker build \
                                -t ${FRONTEND_IMAGE}:${params.FRONTEND_DOCKER_TAG} .
                            """

                            sh """
                                trivy image \
                                ${FRONTEND_IMAGE}:${params.FRONTEND_DOCKER_TAG}
                            """
                        }
                    }
                }
            }
        }

    
   
        stage("Docker Push") {
            steps {
                script {

                    withCredentials([
                        usernamePassword(
                            credentialsId: 'dockerlogin',
                            usernameVariable: 'Dockerhub_user',
                            passwordVariable: 'Dockerhub_pass'
                        )
                    ]) {

                        sh '''
                            echo "$Dockerhub_pass" | docker login \
                            -u "$Dockerhub_user" \
                            --password-stdin
                        '''

                        sh """
                            docker push ${FRONTEND_IMAGE}:${params.FRONTEND_DOCKER_TAG}
                        """

                        sh """
                            docker push ${BACKEND_IMAGE}:${params.BACKEND_DOCKER_TAG}
                        """
                    }
                }
            }
        }
   
   stage('Update Kubernetes Manifests') {
            steps {
                
                sh """
                    sed -i "s|image:.*kevinjcloud/frontend.*|image: ${FRONTEND_IMAGE}:${params.FRONTEND_DOCKER_TAG}|g" \
                     "k8s manifest/frontend.yaml"

                      sed -i "s|image:.*kevinjcloud/backend.*|image: ${BACKEND_IMAGE}:${params.BACKEND_DOCKER_TAG}|g" \
                      "k8s manifest/backend.yaml"
                """
                
            }
        }

    stage("Git Push") {
    steps {
        withCredentials([
            gitUsernamePassword(
                credentialsId: 'git-token',
                gitToolName: 'Default'
            )
        ]) {
            sh '''
                git config user.name "KevinJCloud"
                git config user.email "jobinjkumar@gmail.com"

                git add "k8s manifest/"

                git commit -m "Update Kubernetes images" || true

                git push origin HEAD:main
            '''
        }
    }
}
    
    
        
    
    }

    
    
    

    post{
         success {
            echo "CI completed successfully."
            echo "Argo CD will detect the Kubernetes manifest change and deploy."
        }

        failure {
            echo "CI pipeline failed."
        }
    }

}
