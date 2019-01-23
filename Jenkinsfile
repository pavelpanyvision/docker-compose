#!/usr/bin/env groovy
import hudson.model.*

timeout(time: 120, unit: 'MINUTES') {
    node('master') {

        try {

            // Clean up work space
            step([$class: 'WsCleanup'])

            checkout changelog: false, poll: false, scm: [
                    $class: 'GitSCM',
                    branches: [[name: '*/"${GIT_BRANCH_NAME}"']],
                    extensions: [[$class: 'SparseCheckoutPaths', sparseCheckoutPaths: [[path: 'InstallBuilder/Jenkinsfile_installation']]]],
                    userRemoteConfigs: [[credentialsId: 'av-jenkins-reader', url: "https://github.com/AnyVisionltd/docker-compose.git"]]
            ]

            //load remote jenkins_pipeline
            def generic_pipeline = load "InstallBuilder/Jenkinsfile_installation"
            //start remote jenkins_pipeline
            generic_pipeline.generic_pipeline_method()
            
        } //end catch
        catch(err){

            throw err
            exit 1
        } //end catch
    } // end of node
} //end of timeout
1