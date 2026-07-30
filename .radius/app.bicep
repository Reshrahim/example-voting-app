extension radius

param environment string

@description('Workflow-managed deploy image tag (injected by the deploy pipeline). Unused: containers reference the published upstream images directly.')
param image string = ''

@description('Workflow-managed GHCR registry username (injected by the deploy pipeline). Unused: the referenced images are public.')
param registryUsername string = ''

@secure()
@description('Workflow-managed GHCR registry password (injected by the deploy pipeline). Unused: the referenced images are public.')
param registryPassword string = ''

@secure()
param postgresPassword string

resource votingApp 'Radius.Core/applications@2025-08-01-preview' = {
  name: 'example-voting-app'
  properties: {
    environment: environment
  }
}

resource redisCache 'Radius.Data/redisCaches@2025-08-01-preview' = {
  name: 'reabdul-evapp-redis'
  properties: {
    environment: environment
    application: votingApp.id
    size: 'S'
  }
}

resource postgresDb 'Radius.Data/postgreSqlDatabases@2025-08-01-preview' = {
  name: 'reabdul-evapp-postgres'
  properties: {
    environment: environment
    application: votingApp.id
    size: 'S'
    database: 'postgres'
    username: 'postgres'
    password: postgresPassword
  }
}

resource voteContainer 'Radius.Compute/containers@2025-08-01-preview' = {
  name: 'vote'
  properties: {
    environment: environment
    application: votingApp.id
    containers: {
      vote: {
        image: 'ghcr.io/dockersamples/example-voting-app-vote:latest'
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
        image: 'ghcr.io/dockersamples/example-voting-app-result:latest'
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
        image: 'ghcr.io/dockersamples/example-voting-app-worker:latest'
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
