{
  asList(name, data, parameters):: {
    apiVersion: 'v1',
    kind: 'Template',
    metadata: {
      name: name,
    },
    objects: [data[k] for k in std.objectFields(data)],
    parameters: parameters,
  },

  withResourceRequestsAndLimits(containerName, requests, limits):: {
    local varContainerName = std.strReplace(containerName, '-', '_'),
    local setResourceRequestsAndLimits(object) =
      if object.kind == 'StatefulSet' then {
        spec+: {
          template+: {
            spec+: {
              containers: [
                if c.name == containerName then
                  c {
                    resources: {
                      requests: {
                        cpu: '${' + std.asciiUpper(varContainerName) + '_CPU_REQUEST}',
                        memory: '${' + std.asciiUpper(varContainerName) + '_MEMORY_REQUEST}',
                      },
                      limits: {
                        cpu: '${' + std.asciiUpper(varContainerName) + '_CPU_LIMIT}',
                        memory: '${' + std.asciiUpper(varContainerName) + '_MEMORY_LIMIT}',
                      },
                    },
                  }
                else c
                for c in super.containers
              ],
            },
          },
        },
      }
      else {},
    objects: [
      o + setResourceRequestsAndLimits(o)
      for o in super.objects
    ],
    parameters+: [
      { name: std.asciiUpper(varContainerName) + '_CPU_REQUEST', value: if std.objectHas(requests, 'cpu') then requests.cpu else '100m' },
      { name: std.asciiUpper(varContainerName) + '_CPU_LIMIT', value: if std.objectHas(limits, 'cpu') then limits.cpu else '1' },
      { name: std.asciiUpper(varContainerName) + '_MEMORY_REQUEST', value: if std.objectHas(requests, 'memory') then requests.memory else '500Mi' },
      { name: std.asciiUpper(varContainerName) + '_MEMORY_LIMIT', value: if std.objectHas(limits, 'memory') then limits.memory else '1Gi' },
    ],
  },

  withAuthorizeURL(_config):: {
    local setAuthorizeURL(object) =
      if object.kind == 'StatefulSet' then {
        spec+: {
          template+: {
            spec+: {
              containers: [
                c {
                  command: [
                    if std.startsWith(c, '--authorize=') then '--authorize=${AUTHORIZE_URL}' else c
                    for c in super.command
                  ],
                }
                for c in super.containers
              ],
            },
          },
        },
      }
      else {},
    objects: [
      o + setAuthorizeURL(o)
      for o in super.objects
    ],
    parameters+: [
      { name: 'AUTHORIZE_URL', value: _config.telemeterServer.authorizeURL },
    ],
  },

  withPrometheusImage(_config):: {
    local setImage(object) =
      if object.kind == 'Prometheus' then {
        spec+: {
          baseImage: '${PROMETHEUS_IMAGE}',
          version: '${PROMETHEUS_IMAGE_TAG}',
          containers: [
            if c.name == 'prometheus-proxy' then c {
              image: '${PROXY_IMAGE}:${PROXY_IMAGE_TAG}',
            } else c
            for c in super.containers
          ],
        },
      }
      else {},
    objects: [
      o + setImage(o)
      for o in super.objects
    ],
    parameters+: [
      { name: 'PROMETHEUS_IMAGE', value: _config.imageRepos.prometheus },
      { name: 'PROMETHEUS_IMAGE_TAG', value: _config.versions.prometheus },
      { name: 'PROXY_IMAGE', value: _config.imageRepos.openshiftOauthProxy },
      { name: 'PROXY_IMAGE_TAG', value: _config.versions.openshiftOauthProxy },
    ],
  },

  withPrometheusResources(requests, limits):: {
    local setResources(object, requests, limits) =
      if object.kind == 'Prometheus' then {
        spec+: {
          resources: {
            requests: {
              cpu: '${PROMETHEUS_CPU_REQUEST}',
              memory: '${PROMETHEUS_MEMORY_REQUEST}',
            },
            limits: {
              cpu: '${PROMETHEUS_CPU_LIMIT}',
              memory: '${PROMETHEUS_MEMORY_LIMIT}',
            },
          },
        },
      }
      else {},
    objects: [
      o + setResources(o, requests, limits)
      for o in super.objects
    ],
    parameters+: [
      { name: 'PROMETHEUS_CPU_REQUEST', value: if std.objectHas(requests, 'cpu') then requests.cpu else '0' },
      { name: 'PROMETHEUS_CPU_LIMIT', value: if std.objectHas(limits, 'cpu') then limits.cpu else '0' },
      { name: 'PROMETHEUS_MEMORY_REQUEST', value: if std.objectHas(requests, 'memory') then requests.memory else '0' },
      { name: 'PROMETHEUS_MEMORY_LIMIT', value: if std.objectHas(limits, 'memory') then limits.memory else '0' },
    ],
  },

  withServerImage(_config):: {
    local setImage(object) =
      if object.kind == 'StatefulSet' then {
        spec+: {
          template+: {
            spec+: {
              containers: [
                c {
                  image: if c.name == 'telemeter-server' then '${IMAGE}:${IMAGE_TAG}' else c.image,
                }
                for c in super.containers
              ],
            },
          },
        },
      }
      else {},
    objects: [
      o + setImage(o)
      for o in super.objects
    ],
    parameters+: [
      { name: 'IMAGE', value: _config.imageRepos.telemeterServer },
      { name: 'IMAGE_TAG', value: _config.versions.telemeterServer },
    ],
  },

  withNamespace(_config):: {
    local setPermissions(object) =
      if object.kind == 'Prometheus' then {
        spec+: {
          containers: [
            c {
              args: [
                if std.startsWith(arg, '-openshift-sar') then
                  '-openshift-sar={"resource": "namespaces", "verb": "get", "name": "${NAMESPACE}", "namespace": "${NAMESPACE}"}'
                else if std.startsWith(arg, '-openshift-delegate-urls') then
                  '-openshift-delegate-urls={"/": {"resource": "namespaces", "verb": "get", "name": "${NAMESPACE}", "namespace": "${NAMESPACE}"}}'
                else arg
                for arg in super.args
              ],
            }
            for c in super.containers
          ],
        },
      }
      else {},
    local setNamespace(object) =
      if std.objectHas(object, 'metadata') && std.objectHas(object.metadata, 'namespace') then {
        metadata+: {
          namespace: '${NAMESPACE}',
        },
      }
      else {},
    local setSubjectNamespace(object) =
      if std.endsWith(object.kind, 'Binding') then {
        subjects: [
          s { namespace: '${NAMESPACE}' }
          for s in super.subjects
        ],
      }
      else {},
    local setClusterRoleRuleNamespace(object) =
      if object.kind == 'ClusterRole' then {
        rules: [
          r + if std.objectHas(r, 'resources') && r.resources[0] == 'namespaces' then {
            resourceNames: ['${NAMESPACE}'],
          } else {}
          for r in super.rules
        ],
      }
      else {},
    local setServiceMonitorServerNameNamespace(object) =
      if object.kind == 'ServiceMonitor' then {
        spec+: {
          endpoints: [
            e + if std.objectHas(e, 'tlsConfig') then {
              tlsConfig+: if std.length(std.split(super.tlsConfig.serverName, '.')) == 3 && std.split(super.tlsConfig.serverName, '.')[1] == _config.namespace && std.split(e.tlsConfig.serverName, '.')[2] == 'svc' then {
                serverName: '%s.%s.svc' % [std.split(e.tlsConfig.serverName, '.')[0], '${NAMESPACE}'],
              } else {},
            } else {}
            for e in super.endpoints
          ],
        },
      }
      else {},
    local namespaceNonNamespacedObjects(object) =
      (if std.objectHas(object, 'metadata') && !std.objectHas(object.metadata, 'namespace') && std.objectHas(object.metadata, 'name') then {
         metadata+: {
           name: '%s-${NAMESPACE}' % super.name,
         },
       }
       else {}) +
      (if object.kind == 'ClusterRoleBinding' then {
         roleRef+: {
           name: '%s-${NAMESPACE}' % super.name,
         },
       }
       else {}),

    local setMemcachedNamespace(object) =
      if object.kind == 'StatefulSet' then {
        spec+: {
          template+: {
            spec+: {
              containers: [
                c + (if std.objectHas(c, 'command') then {
                       command: [
                         if std.startsWith(c, '--memcached=') then std.join('.', std.splitLimit(c, '.', 2)[:2] + ['${NAMESPACE}'] + [std.splitLimit(c, '.', 3)[3]]) else c
                         for c in super.command
                       ],
                     } else {})
                for c in super.containers
              ],
            },
          },
        },
      }
      else {},

    objects: [
      o + setNamespace(o) + setSubjectNamespace(o) + setPermissions(o) + setServiceMonitorServerNameNamespace(o) + setClusterRoleRuleNamespace(o) + namespaceNonNamespacedObjects(o) + setMemcachedNamespace(o)
      for o in super.objects
    ],
    parameters+: [
      { name: 'NAMESPACE', value: _config.namespace },
    ],
  },
}
