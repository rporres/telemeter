local list = import 'lib/list.libsonnet';

(import 'server/kubernetes.libsonnet') + {
  local ts = super.telemeterServer,
  telemeterServer+:: {
    list: list.asList('telemeter', ts, [])
          + list.withAuthorizeURL($._config)
          + list.withNamespace($._config)
          + list.withServerImage($._config)
          + list.withResourceRequestsAndLimits($._config)
  },
} + {
  _config+:: {
    jobs+: {
      TelemeterServer: 'job="telemeter-server"',
    },
    telemeterServer+: {
      whitelist+: (import 'metrics.jsonnet'),
      elideLabels+: [
        'prometheus_replica',
      ],
      // resourceLimits: {
      //   cpu: '1',
      //   memory: '1Gi',
      // },
      // resourceRequests: {
      //   cpu: '0.2',
      //   memory: '100Mi',
      // },
    },
  },
}
