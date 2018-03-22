node('linux') {
  checkout scm  
  stage('checkout sonar-enterprise') {
    // Using credentials of sonartech user
    git credentialsId: '765cc011-6f03-4509-992e-62b49c3fccfd', url: 'git@github.com:SonarSource/sonar-enterprise.git'
  }

  stage('sync') {
    dir('sonar-enterprise'){
      sh '../sync_public_master.sh'
    }
  }

  stage('commit') {
    dir('sonar-enterprise'){
      sh '../sync_public_master.sh'
    }
  }
}