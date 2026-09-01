extension radius

param environment string

@description('Password/token for the OCI registry the containerImages recipe pushes to (a GitHub token with write:packages for ghcr.io).')
@secure()
param registryPassword string

@description('Username for the OCI registry the containerImages recipe pushes to (the GitHub actor for ghcr.io).')
@secure()
param registryUsername string

resource exampleVotingApp 'Radius.Core/applications@2025-08-01-preview' = {
  name: 'example-voting-app'
  properties: {
    environment: environment
  }
}

resource mongoDb 'Radius.Data/mongoDatabases@2025-08-01-preview' = {
  name: 'db'
  properties: {
    environment: environment
    application: exampleVotingApp.id
    codeReference: 'result/server.js#L13'
    database: 'votes'
  }
}

resource redisCache 'Radius.Data/redisCaches@2025-08-01-preview' = {
  name: 'redis'
  properties: {
    environment: environment
    application: exampleVotingApp.id
    codeReference: 'vote/app.py#L21'
  }
}

resource registryCreds 'Radius.Security/secrets@2025-08-01-preview' = {
  name: 'radius-ghcr-registry-creds'
  properties: {
    environment: environment
    application: exampleVotingApp.id
    codeReference: '.radius/app.bicep'
    data: {
      password: {
        value: registryPassword
      }
      username: {
        value: registryUsername
      }
    }
  }
}

resource resultImage 'Radius.Compute/containerImages@2025-08-01-preview' = {
  name: 'result-image'
  properties: {
    environment: environment
    application: exampleVotingApp.id
    codeReference: 'result/Dockerfile'
    build: {
      platforms: [
        'linux/amd64'
      ]
      source: 'git::https://github.com/Reshrahim/example-voting-app.git//result?ref=63e9150ca17af4ed05880d4245e486481f73fcb4'
    }
  }
  dependsOn: [
    registryCreds
  ]
}

resource voteImage 'Radius.Compute/containerImages@2025-08-01-preview' = {
  name: 'vote-image'
  properties: {
    environment: environment
    application: exampleVotingApp.id
    codeReference: 'vote/Dockerfile'
    build: {
      platforms: [
        'linux/amd64'
      ]
      source: 'git::https://github.com/Reshrahim/example-voting-app.git//vote?ref=63e9150ca17af4ed05880d4245e486481f73fcb4'
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
    application: exampleVotingApp.id
    codeReference: 'worker/Dockerfile'
    build: {
      source: 'git::https://github.com/Reshrahim/example-voting-app.git//worker?ref=63e9150ca17af4ed05880d4245e486481f73fcb4'
    }
  }
  dependsOn: [
    registryCreds
  ]
}

resource resultContainer 'Radius.Compute/containers@2025-08-01-preview' = {
  name: 'result'
  properties: {
    environment: environment
    application: exampleVotingApp.id
    codeReference: 'result/server.js#L78'
    containers: {
      result: {
        image: resultImage.properties.imageReference
        env: {
          MONGO_DATABASE: {
            value: 'votes'
          }
          MONGO_URL: {
            valueFrom: {
              secretKeyRef: {
                key: 'connectionString'
                secretName: mongoDb.properties.secrets.name
              }
            }
          }
        }
        ports: {
          web: {
            containerPort: 80
          }
        }
      }
    }
    connections: {
      mongodb: {
        source: mongoDb.id
      }
    }
  }
}

resource voteContainer 'Radius.Compute/containers@2025-08-01-preview' = {
  name: 'vote'
  properties: {
    environment: environment
    application: exampleVotingApp.id
    codeReference: 'vote/app.py#L13'
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

resource workerContainer 'Radius.Compute/containers@2025-08-01-preview' = {
  name: 'worker'
  properties: {
    environment: environment
    application: exampleVotingApp.id
    codeReference: 'worker/Program.cs#L21'
    containers: {
      worker: {
        image: workerImage.properties.imageReference
        env: {
          MONGO_DATABASE: {
            value: 'votes'
          }
          MONGO_URL: {
            valueFrom: {
              secretKeyRef: {
                key: 'connectionString'
                secretName: mongoDb.properties.secrets.name
              }
            }
          }
        }
      }
    }
    connections: {
      mongodb: {
        source: mongoDb.id
      }
      rediscache: {
        source: redisCache.id
      }
    }
  }
}
