node('linux') {
    
  stage('checkout sonar-cpp') {
    // Using credentials of sonartech user
    git credentialsId: '765cc011-6f03-4509-992e-62b49c3fccfd', url: 'git@github.com:SonarSource/sonar-enterprise.git'
  }

  stage('sync') {
    sh './sync_public_master.sh'
  }

  stage('commit') {
    sh './sync_public_master.sh'
  }
}