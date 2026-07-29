extension radius

param environment string

@secure()
param postgresPassword string

param registryUsername string

@secure()
param registryPassword string

resource votingApp 'Radius.Core/applications@2025-08-01-preview' = {
  name: 'example-voting-app'
  properties: {
    environment: environment
  }
}

resource redisCache 'Radius.Data/redisCaches@2025-08-01-preview' = {
  name: 'redis'
  properties: {
    environment: environment
    application: votingApp.id
  }
}

resource postgresDb 'Radius.Data/postgreSqlDatabases@2025-08-01-preview' = {
  name: 'postgres'
  properties: {
    environment: environment
    application: votingApp.id
    database: 'postgres'
    username: 'postgres'
    password: postgresPassword
  }
}

resource registryCreds 'Radius.Security/secrets@2025-08-01-preview' = {
  name: 'radius-ghcr-registry-creds'
  properties: {
    environment: environment
    application: votingApp.id
    data: {
      username: {
        value: registryUsername
      }
      password: {
        value: registryPassword
      }
    }
  }
}

resource voteImage 'Radius.Compute/containerImages@2025-08-01-preview' = {
  name: 'vote-image'
  properties: {
    environment: environment
    application: votingApp.id
    build: {
      source: 'git::https://github.com/dockersamples/example-voting-app.git//vote?ref=63e9150ca17af4ed05880d4245e486481f73fcb4'
    }
  }
  dependsOn: [
    registryCreds
  ]
}

resource resultImage 'Radius.Compute/containerImages@2025-08-01-preview' = {
  name: 'result-image'
  properties: {
    environment: environment
    application: votingApp.id
    build: {
      source: 'git::https://github.com/dockersamples/example-voting-app.git//result?ref=63e9150ca17af4ed05880d4245e486481f73fcb4'
    }
  }
  dependsOn: [
    registryCreds
  ]
}

resource workerImage 'Radius.Compute/containerImages@2025-08-01-preview' = {
  name: 'worker-image'
  properties: {
    environment: environment
    application: votingApp.id
    build: {
      source: 'git::https://github.com/dockersamples/example-voting-app.git//worker?ref=63e9150ca17af4ed05880d4245e486481f73fcb4'
    }
  }
  dependsOn: [
    registryCreds
  ]
}

resource voteContainer 'Radius.Compute/containers@2025-08-01-preview' = {
  name: 'vote'
  properties: {
    environment: environment
    application: votingApp.id
    containers: {
      vote: {
        image: voteImage.properties.imageReference
        ports: {
          web: {
            containerPort: 80
          }
        }
      }
    }
    connections: {
      rediscache: {
        source: redisCache.id
      }
    }
  }
}

resource resultContainer 'Radius.Compute/containers@2025-08-01-preview' = {
  name: 'result'
  properties: {
    environment: environment
    application: votingApp.id
    containers: {
      result: {
        image: resultImage.properties.imageReference
        ports: {
          web: {
            containerPort: 80
          }
        }
      }
    }
    connections: {
      postgresdb: {
        source: postgresDb.id
      }
    }
  }
}

resource workerContainer 'Radius.Compute/containers@2025-08-01-preview' = {
  name: 'worker'
  properties: {
    environment: environment
    application: votingApp.id
    containers: {
      worker: {
        image: workerImage.properties.imageReference
      }
    }
    connections: {
      rediscache: {
        source: redisCache.id
      }
      postgresdb: {
        source: postgresDb.id
      }
    }
  }
}
