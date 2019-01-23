#!/usr/bin/env groovy
import hudson.model.*

timeout(time: 120, unit: 'MINUTES') {
    node('master') {

        try {

            // Clean up work space
            step([$class: 'WsCleanup'])

            checkout changelog: false, poll: false, scm: [
                    $class: 'GitSCM',
                    branches: [[name: '*/master']],
                    extensions: [[$class: 'SparseCheckoutPaths', sparseCheckoutPaths: [[path: 'InstallBuilder/Jenkins_installation']]]],
                    userRemoteConfigs: [[credentialsId: 'av-jenkins-reader', url: "https://github.com/AnyVisionltd/docker-compose.git"]]
            ]

            //load remote jenkins_pipeline
            def generic_pipeline = load "jenkins/jenkins-pipeline/Jenkinsfile_installation"
            //start remote jenkins_pipeline
            generic_pipeline.generic_pipeline_method()
            
            //load remote Jenkinsfile_airgap
            //def generic_pipeline_airgap = load "jenkins/jenkins-pipeline/Jenkinsfile_airgap"
            //start remote Jenkinsfile_airgap
            //generic_pipeline_airgap.generic_pipeline_method()

        } //end catch
        catch(err){

            throw err
            exit 1
        } //end catch
    } // end of node
} //end of timeout
