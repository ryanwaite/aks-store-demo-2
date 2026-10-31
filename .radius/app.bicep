extension radius

param environment string
@secure()
param rabbitmqPassword string
@secure()
param registryPassword string
@secure()
param registryUsername string
param storeAdminHostname string
param storeFrontHostname string

var storeAdminNginxConfig = '''
server {
    listen 8081;
    listen [::]:8081;
    server_name localhost;
    client_max_body_size 10m;
    location / {
        root /usr/share/nginx/html;
        index index.html index.htm;
        try_files $uri $uri/ /index.html;
    }
    error_page 500 502 503 504 /50x.html;
    location = /50x.html {
        root /usr/share/nginx/html;
    }
    location /health {
        default_type application/json;
        return 200 '{"status":"ok","version":"0.1.0"}';
    }
    location ~ ^/api/makeline/order/(?<id>\w+) {
        proxy_pass http://MAKELINE_HOST:3001/order/$id;
        proxy_http_version 1.1;
    }
    location /api/makeline/order {
        proxy_pass http://MAKELINE_HOST:3001/order;
        proxy_http_version 1.1;
    }
    location /api/makeline/order/fetch {
        proxy_pass http://MAKELINE_HOST:3001/order/fetch;
        proxy_http_version 1.1;
    }
    location /api/order {
        rewrite ^/api/order$ / break;
        rewrite ^/api/order(/.*)$ $1 break;
        proxy_pass http://ORDER_HOST:3000;
        proxy_http_version 1.1;
    }
    location /api/products/ {
        proxy_pass http://PRODUCT_HOST:3002/;
        proxy_http_version 1.1;
    }
    location /api/products {
        rewrite ^/api/products$ / break;
        rewrite ^/api/products(/.*)$ $1 break;
        proxy_pass http://PRODUCT_HOST:3002;
        proxy_http_version 1.1;
    }
    location ~ ^/api/product/(?<id>\w+) {
        proxy_pass http://PRODUCT_HOST:3002/$id;
        proxy_http_version 1.1;
    }
    location /api/product {
        rewrite ^/api/product$ / break;
        rewrite ^/api/product(/.*)$ $1 break;
        proxy_pass http://PRODUCT_HOST:3002;
        proxy_http_version 1.1;
    }
    location /api/product/ {
        proxy_pass http://PRODUCT_HOST:3002/;
        proxy_http_version 1.1;
    }
    location /api/ai/health {
        proxy_pass http://PRODUCT_HOST:3002/ai/health;
        proxy_http_version 1.1;
    }
    location /api/ai/generate/description {
        proxy_pass http://PRODUCT_HOST:3002/ai/generate/description;
        proxy_http_version 1.1;
    }
    location /api/ai/generate/image {
        proxy_pass http://PRODUCT_HOST:3002/ai/generate/image;
        proxy_http_version 1.1;
        proxy_connect_timeout 30s;
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
    }
}
'''
var storeFrontNginxConfig = '''
server {
    listen 8080;
    listen [::]:8080;
    server_name localhost;
    location / {
        root /usr/share/nginx/html;
        index index.html index.htm;
        try_files $uri $uri/ /index.html;
    }
    error_page 500 502 503 504 /50x.html;
    location = /50x.html {
        root /usr/share/nginx/html;
    }
    location /health {
        default_type application/json;
        return 200 '{"status":"ok","version":"0.1.0"}';
    }
    location /api/orders {
        rewrite ^/api/orders$ / break;
        rewrite ^/api/orders(/.*)$ $1 break;
        proxy_pass http://ORDER_HOST:3000;
        proxy_http_version 1.1;
    }
    location /api/products {
        rewrite ^/api/products$ / break;
        rewrite ^/api/products(/.*)$ $1 break;
        proxy_pass http://PRODUCT_HOST:3002;
        proxy_http_version 1.1;
    }
}
'''

resource aksStoreApp 'Radius.Core/applications@2025-08-01-preview' = {
  name: 'aks-store-demo-2'
  properties: {
    environment: environment
  }
}

resource mongoDb 'Radius.Data/mongoDatabases@2025-08-01-preview' = {
  name: 'mongo'
  properties: {
    environment: environment
    application: aksStoreApp.id
    codeReference: 'src/makeline-service/mongodb.go#L127'
    database: 'orderdb'
  }
}

resource rabbitmqQueue 'Radius.Messaging/rabbitMQ@2025-08-01-preview' = {
  name: 'rabbitmq'
  properties: {
    environment: environment
    application: aksStoreApp.id
    codeReference: 'src/order-service/plugins/messagequeue.js#L26'
    password: rabbitmqSecret.id
    queue: 'orders'
    username: 'myadmin'
  }
}

resource rabbitmqSecret 'Radius.Security/secrets@2025-08-01-preview' = {
  name: 'rabbitmq-secret'
  properties: {
    environment: environment
    application: aksStoreApp.id
    codeReference: 'src/order-service/plugins/messagequeue.js#L30'
    data: {
      password: {
        value: rabbitmqPassword
      }
    }
  }
}

// Do not change this Secret's name value from 'radius-ghcr-registry-creds'.
// The containerImages recipe looks up registry credentials by that fixed name.
resource registryCreds 'Radius.Security/secrets@2025-08-01-preview' = {
  name: 'radius-ghcr-registry-creds'
  properties: {
    environment: environment
    application: aksStoreApp.id
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

resource makelineServiceImage 'Radius.Compute/containerImages@2025-08-01-preview' = {
  name: 'makeline-service-image'
  properties: {
    environment: environment
    application: aksStoreApp.id
    codeReference: 'src/makeline-service/Dockerfile'
    build: {
      source: 'git::https://github.com/ryanwaite/aks-store-demo-2.git//src/makeline-service?ref=d752f0b4f7edc22159c7529a6cd7956099b6d819'
      platforms: [
        'linux/amd64'
      ]
    }
  }
  dependsOn: [
    registryCreds
  ]
}

resource orderServiceImage 'Radius.Compute/containerImages@2025-08-01-preview' = {
  name: 'order-service-image'
  properties: {
    environment: environment
    application: aksStoreApp.id
    codeReference: 'src/order-service/Dockerfile'
    build: {
      source: 'git::https://github.com/ryanwaite/aks-store-demo-2.git//src/order-service?ref=d752f0b4f7edc22159c7529a6cd7956099b6d819'
      platforms: [
        'linux/amd64'
      ]
    }
  }
  dependsOn: [
    registryCreds
  ]
}

resource productServiceImage 'Radius.Compute/containerImages@2025-08-01-preview' = {
  name: 'product-service-image'
  properties: {
    environment: environment
    application: aksStoreApp.id
    codeReference: 'src/product-service/Dockerfile'
    build: {
      source: 'git::https://github.com/ryanwaite/aks-store-demo-2.git//src/product-service?ref=d752f0b4f7edc22159c7529a6cd7956099b6d819'
      platforms: [
        'linux/amd64'
      ]
    }
  }
  dependsOn: [
    registryCreds
  ]
}

resource storeAdminImage 'Radius.Compute/containerImages@2025-08-01-preview' = {
  name: 'store-admin-image'
  properties: {
    environment: environment
    application: aksStoreApp.id
    codeReference: 'src/store-admin/Dockerfile'
    build: {
      source: 'git::https://github.com/ryanwaite/aks-store-demo-2.git//src/store-admin?ref=d752f0b4f7edc22159c7529a6cd7956099b6d819'
      platforms: [
        'linux/amd64'
      ]
    }
  }
  dependsOn: [
    registryCreds
  ]
}

resource storeFrontImage 'Radius.Compute/containerImages@2025-08-01-preview' = {
  name: 'store-front-image'
  properties: {
    environment: environment
    application: aksStoreApp.id
    codeReference: 'src/store-front/Dockerfile'
    build: {
      source: 'git::https://github.com/ryanwaite/aks-store-demo-2.git//src/store-front?ref=d752f0b4f7edc22159c7529a6cd7956099b6d819'
      platforms: [
        'linux/amd64'
      ]
    }
  }
  dependsOn: [
    registryCreds
  ]
}

resource virtualCustomerImage 'Radius.Compute/containerImages@2025-08-01-preview' = {
  name: 'virtual-customer-image'
  properties: {
    environment: environment
    application: aksStoreApp.id
    codeReference: 'src/virtual-customer/Dockerfile'
    build: {
      source: 'git::https://github.com/ryanwaite/aks-store-demo-2.git//src/virtual-customer?ref=d752f0b4f7edc22159c7529a6cd7956099b6d819'
      platforms: [
        'linux/amd64'
      ]
    }
  }
  dependsOn: [
    registryCreds
  ]
}

resource virtualWorkerImage 'Radius.Compute/containerImages@2025-08-01-preview' = {
  name: 'virtual-worker-image'
  properties: {
    environment: environment
    application: aksStoreApp.id
    codeReference: 'src/virtual-worker/Dockerfile'
    build: {
      source: 'git::https://github.com/ryanwaite/aks-store-demo-2.git//src/virtual-worker?ref=d752f0b4f7edc22159c7529a6cd7956099b6d819'
      platforms: [
        'linux/amd64'
      ]
    }
  }
  dependsOn: [
    registryCreds
  ]
}

resource makelineServiceContainer 'Radius.Compute/containers@2025-08-01-preview' = {
  name: 'makeline-service'
  properties: {
    environment: environment
    application: aksStoreApp.id
    codeReference: 'src/makeline-service/main.go#L21'
    containers: {
      makelineService: {
        image: makelineServiceImage.properties.imageReference
        env: {
          ORDER_DB_COLLECTION_NAME: {
            value: 'orders'
          }
          ORDER_DB_NAME: {
            value: mongoDb.properties.database
          }
          ORDER_DB_URI: {
            valueFrom: {
              secretKeyRef: {
                secretName: mongoDb.properties.secrets.name
                key: 'connectionString'
              }
            }
          }
          ORDER_QUEUE_NAME: {
            value: rabbitmqQueue.properties.queue
          }
          ORDER_QUEUE_PASSWORD: {
            valueFrom: {
              secretKeyRef: {
                secretName: rabbitmqSecret.name
                key: 'password'
              }
            }
          }
          ORDER_QUEUE_URI: {
            value: 'amqp://${rabbitmqQueue.properties.host}:${rabbitmqQueue.properties.port}'
          }
          ORDER_QUEUE_USERNAME: {
            value: rabbitmqQueue.properties.username
          }
        }
        ports: {
          web: {
            containerPort: 3001
          }
        }
        readinessProbe: {
          httpGet: {
            path: '/health'
            port: 3001
          }
          initialDelaySeconds: 3
          periodSeconds: 5
        }
      }
    }
  }
}

resource orderServiceContainer 'Radius.Compute/containers@2025-08-01-preview' = {
  name: 'order-service'
  properties: {
    environment: environment
    application: aksStoreApp.id
    codeReference: 'src/order-service/app.js#L6'
    containers: {
      orderService: {
        image: orderServiceImage.properties.imageReference
        env: {
          FASTIFY_ADDRESS: {
            value: '0.0.0.0'
          }
          ORDER_QUEUE_HOSTNAME: {
            value: rabbitmqQueue.properties.host
          }
          ORDER_QUEUE_NAME: {
            value: rabbitmqQueue.properties.queue
          }
          ORDER_QUEUE_PASSWORD: {
            valueFrom: {
              secretKeyRef: {
                secretName: rabbitmqSecret.name
                key: 'password'
              }
            }
          }
          ORDER_QUEUE_PORT: {
            value: string(rabbitmqQueue.properties.port)
          }
          ORDER_QUEUE_USERNAME: {
            value: rabbitmqQueue.properties.username
          }
        }
        ports: {
          web: {
            containerPort: 3000
          }
        }
        readinessProbe: {
          httpGet: {
            path: '/health'
            port: 3000
          }
          initialDelaySeconds: 3
          periodSeconds: 5
        }
      }
      waitForRabbitmq: {
        image: 'busybox:1.37.0'
        initContainer: true
        command: [
          'sh'
          '-c'
        ]
        args: [
          'until nc -z "$RABBITMQ_HOST" "$RABBITMQ_PORT"; do echo waiting for rabbitmq; sleep 2; done'
        ]
        env: {
          RABBITMQ_HOST: {
            value: rabbitmqQueue.properties.host
          }
          RABBITMQ_PORT: {
            value: string(rabbitmqQueue.properties.port)
          }
        }
      }
    }
  }
}

resource productServiceContainer 'Radius.Compute/containers@2025-08-01-preview' = {
  name: 'product-service'
  properties: {
    environment: environment
    application: aksStoreApp.id
    codeReference: 'src/product-service/src/main.rs#L5'
    containers: {
      productService: {
        image: productServiceImage.properties.imageReference
        ports: {
          web: {
            containerPort: 3002
          }
        }
        readinessProbe: {
          httpGet: {
            path: '/health'
            port: 3002
          }
          initialDelaySeconds: 3
          periodSeconds: 5
        }
      }
    }
  }
}

resource storeAdminContainer 'Radius.Compute/containers@2025-08-01-preview' = {
  name: 'store-admin'
  properties: {
    environment: environment
    application: aksStoreApp.id
    codeReference: 'src/store-admin/src/main.ts#L8'
    containers: {
      storeAdmin: {
        image: storeAdminImage.properties.imageReference
        command: [
          'sh'
          '-c'
        ]
        args: [
          'set -eu; printf \'%s\\n\' "$NGINX_CONFIG" > /etc/nginx/conf.d/default.conf; exec nginx -g \'daemon off;\''
        ]
        env: {
          NGINX_CONFIG: {
            value: replace(replace(replace(storeAdminNginxConfig, 'MAKELINE_HOST', makelineServiceContainer.properties.hosts['makelineService']), 'ORDER_HOST', orderServiceContainer.properties.hosts['orderService']), 'PRODUCT_HOST', productServiceContainer.properties.hosts['productService'])
          }
        }
        ports: {
          web: {
            containerPort: 8081
          }
        }
        readinessProbe: {
          httpGet: {
            path: '/health'
            port: 8081
          }
          initialDelaySeconds: 3
          periodSeconds: 5
        }
      }
    }
  }
}

resource storeFrontContainer 'Radius.Compute/containers@2025-08-01-preview' = {
  name: 'store-front'
  properties: {
    environment: environment
    application: aksStoreApp.id
    codeReference: 'src/store-front/src/main.ts#L8'
    containers: {
      storeFront: {
        image: storeFrontImage.properties.imageReference
        command: [
          'sh'
          '-c'
        ]
        args: [
          'set -eu; printf \'%s\\n\' "$NGINX_CONFIG" > /etc/nginx/conf.d/default.conf; exec nginx -g \'daemon off;\''
        ]
        env: {
          NGINX_CONFIG: {
            value: replace(replace(storeFrontNginxConfig, 'ORDER_HOST', orderServiceContainer.properties.hosts['orderService']), 'PRODUCT_HOST', productServiceContainer.properties.hosts['productService'])
          }
        }
        ports: {
          web: {
            containerPort: 8080
          }
        }
        readinessProbe: {
          httpGet: {
            path: '/health'
            port: 8080
          }
          initialDelaySeconds: 3
          periodSeconds: 5
        }
      }
    }
  }
}

resource virtualCustomerContainer 'Radius.Compute/containers@2025-08-01-preview' = {
  name: 'virtual-customer'
  properties: {
    environment: environment
    application: aksStoreApp.id
    codeReference: 'src/virtual-customer/src/main.rs#L7'
    containers: {
      virtualCustomer: {
        image: virtualCustomerImage.properties.imageReference
        env: {
          ORDERS_PER_HOUR: {
            value: '100'
          }
          ORDER_SERVICE_URL: {
            value: 'http://${orderServiceContainer.properties.hosts['orderService']}:3000/'
          }
        }
      }
    }
  }
}

resource virtualWorkerContainer 'Radius.Compute/containers@2025-08-01-preview' = {
  name: 'virtual-worker'
  properties: {
    environment: environment
    application: aksStoreApp.id
    codeReference: 'src/virtual-worker/src/main.rs#L6'
    containers: {
      virtualWorker: {
        image: virtualWorkerImage.properties.imageReference
        env: {
          MAKELINE_SERVICE_URL: {
            value: 'http://${makelineServiceContainer.properties.hosts['makelineService']}:3001'
          }
          ORDERS_PER_HOUR: {
            value: '100'
          }
        }
      }
    }
  }
}

resource storeAdminRoute 'Radius.Compute/routes@2025-08-01-preview' = {
  name: 'store-admin-route'
  properties: {
    environment: environment
    application: aksStoreApp.id
    codeReference: 'aks-store-all-in-one.yaml#L498'
    hostnames: [
      storeAdminHostname
    ]
    kind: 'HTTP'
    rules: [
      {
        destinationContainer: {
          containerName: 'storeAdmin'
          containerPort: 8081
          resourceId: storeAdminContainer.id
        }
        matches: [
          {
            httpPath: '/'
          }
        ]
      }
    ]
  }
}

resource storeFrontRoute 'Radius.Compute/routes@2025-08-01-preview' = {
  name: 'store-front-route'
  properties: {
    environment: environment
    application: aksStoreApp.id
    codeReference: 'aks-store-all-in-one.yaml#L435'
    hostnames: [
      storeFrontHostname
    ]
    kind: 'HTTP'
    rules: [
      {
        destinationContainer: {
          containerName: 'storeFront'
          containerPort: 8080
          resourceId: storeFrontContainer.id
        }
        matches: [
          {
            httpPath: '/'
          }
        ]
      }
    ]
  }
}
