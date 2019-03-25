# CloudBees Core kubernetes

---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: cjoc

---
kind: Role
apiVersion: rbac.authorization.k8s.io/v1beta1
metadata:
  name: master-management
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["create","delete","get","list","patch","update","watch"]
- apiGroups: [""]
  resources: ["pods/exec"]
  verbs: ["create","delete","get","list","patch","update","watch"]
- apiGroups: [""]
  resources: ["pods/log"]
  verbs: ["get","list","watch"]
- apiGroups: ["apps"]
  resources: ["statefulsets"]
  verbs: ["create","delete","get","list","patch","update","watch"]
# - apiGroups: [""]
#   resources: ["namespaces"]
#   verbs: ["create","delete","get","list","patch","update","watch"]
- apiGroups: [""]
  resources: ["services"]
  verbs: ["create","delete","get","list","patch","update","watch"]
- apiGroups: [""]
  resources: ["persistentvolumeclaims"]
  verbs: ["create","delete","get","list","patch","update","watch"]
- apiGroups: ["extensions"]
  resources: ["ingresses"]
  verbs: ["create","delete","get","list","patch","update","watch"]
- apiGroups: [""]
  resources: ["secrets"]
  verbs: ["list"]
- apiGroups: [""]
  resources: ["events"]
  verbs: ["get","list","watch"]

---
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: RoleBinding
metadata:
  name: cjoc
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: master-management
  # namespace: myproject
subjects:
- kind: ServiceAccount
  name: cjoc
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: cjoc-configure-jenkins-groovy
data:
  location.groovy: |
    hudson.ExtensionList.lookupSingleton(com.cloudbees.jenkins.support.impl.cloudbees.TcpSlaveAgentListenerMonitor.class).disable(true)
    jenkins.model.JenkinsLocationConfiguration.get().setUrl("http://${DOMAIN_NAME}/cjoc");

---
apiVersion: "apps/v1"
kind: "StatefulSet"
metadata:
  name: cjoc
  labels:
    com.cloudbees.cje.type: cjoc
    com.cloudbees.cje.tenant: cjoc
spec:
  selector:
    matchLabels:
      com.cloudbees.cje.type: cjoc
      com.cloudbees.cje.tenant: cjoc
  serviceName: cjoc
  replicas: 1
  updateStrategy:
    type: RollingUpdate
  template:
    metadata:
      name: cjoc
      labels:
        com.cloudbees.cje.type: cjoc
        com.cloudbees.cje.tenant: cjoc
    spec:
      serviceAccountName: cjoc
      terminationGracePeriodSeconds: 10
      containers:
      - name: jenkins
        image: cloudbees/cloudbees-cloud-core-oc:2.138.4.3
        env:
        - name: ENVIRONMENT
          value: KUBERNETES
        - name: JENKINS_OPTS
          value: --prefix=/cjoc
        - name: JAVA_OPTS
          # To allocate masters using a non-default storage class, add the following
          value: >-
            -XshowSettings:vm
            -XX:MaxRAMFraction=1
            -XX:+UnlockExperimentalVMOptions
            -XX:+UseCGroupMemoryLimitForHeap
            -XX:+PrintGCDetails
            -Dcb.IMProp.warProfiles.cje=kubernetes.json
            -Dcom.cloudbees.opscenter.analytics.reporter.JocAnalyticsReporter.PERIOD=120
            -Dcom.cloudbees.opscenter.analytics.reporter.metrics.AperiodicMetricSubmitter.PERIOD=120
            -Dcom.cloudbees.opscenter.analytics.FeederConfiguration.PERIOD=120
            -Dcom.cloudbees.masterprovisioning.kubernetes.KubernetesMasterProvisioning.fsGroup=1000
            -Dhudson.lifecycle=hudson.lifecycle.ExitLifecycle
            -Dcom.cloudbees.jce.masterprovisioning.DockerImageDefinitionConfiguration.disableAutoConfiguration=true
            -Dcom.cloudbees.jce.masterprovisioning.DockerImageDefinitionConfiguration.masterImageName="CloudBees Core - Managed Master 2.138.4.3 "
            -Dcom.cloudbees.jce.masterprovisioning.DockerImageDefinitionConfiguration.masterImage=cloudbees/cloudbees-core-mm:2.138.4.3
            -Dcom.cloudbees.masterprovisioning.kubernetes.KubernetesMasterProvisioning.storageClassName=ssd
        ports:
        - containerPort: 8080
        - containerPort: 50000
        resources:
          limits:
            cpu: "4"
            memory: "32G"
        volumeMounts:
        - name: jenkins-home
          mountPath: /var/jenkins_home
        - name: jenkins-configure-jenkins-groovy
          mountPath: /var/jenkins_config/configure-jenkins.groovy.d
        livenessProbe:
          httpGet:
            path: /cjoc/login
            port: 8080
          initialDelaySeconds: 300
          timeoutSeconds: 5
      volumes:
      - name: jenkins-configure-jenkins-groovy
        configMap:
          name: cjoc-configure-jenkins-groovy
      securityContext:
        fsGroup: 1000
      imagePullSecrets:
      - name: docker.cloudbees.com
  volumeClaimTemplates:
  - metadata:
      name: jenkins-home
    spec:
      accessModes: [ "ReadWriteOnce" ]
      resources:
        requests:
          storage: 200Gi
      storageClassName: ssd

---
apiVersion: v1
kind: Service
metadata:
  name: cjoc
spec:
  # type: LoadBalancer
  selector:
    com.cloudbees.cje.tenant: cjoc
  ports:
  - name: http
    port: 80
    targetPort: 8080
    protocol: TCP
  - name: jnlp
    port: 50000
    protocol: TCP
---
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: cjoc
  annotations:
    kubernetes.io/ingress.class: "nginx"
    nginx.ingress.kubernetes.io/app-root: "https://$best_http_host/cjoc/teams-check/"
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
    nginx.ingress.kubernetes.io/proxy-body-size: 50m
    nginx.ingress.kubernetes.io/proxy-request-buffering: "off"
    nginx.ingress.kubernetes.io/proxy-connect-timeout: "3600" #
    nginx.ingress.kubernetes.io/proxy-read-timeout: "3600" #
    nginx.ingress.kubernetes.io/proxy-send-timeout: "3600" #
spec:
  # To enable SSL offloading at ingress level, uncomment the following 5 lines
  #tls:
  #- hosts:
  #  - ${DOMAIN_NAME}
  #  # Name of the secret containing the certificate to be used
  #  secretName: cje-example-com-tls
  rules:
  - http:
      paths:
      - path: /cjoc
        backend:
          serviceName: cjoc
          servicePort: 80
    host: ${DOMAIN_NAME}
# Service account for masters
# from https://github.com/jenkinsci/kubernetes-plugin/blob/master/src/main/kubernetes/service-account.yml

---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: jenkins

---
kind: Role
apiVersion: rbac.authorization.k8s.io/v1beta1
metadata:
  name: pods-all
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["create","delete","get","list","patch","update","watch"]
- apiGroups: [""]
  resources: ["pods/exec"]
  verbs: ["create","delete","get","list","patch","update","watch"]
- apiGroups: [""]
  resources: ["pods/log"]
  verbs: ["get","list","watch"]

---
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: RoleBinding
metadata:
  name: jenkins
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: pods-all
  # namespace: myproject
subjects:
- kind: ServiceAccount
  name: jenkins
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: jenkins-agent
data:
  jenkins-agent: |
    #!/usr/bin/env sh

    # The MIT License
    #
    #  Copyright (c) 2015, CloudBees, Inc.
    #
    #  Permission is hereby granted, free of charge, to any person obtaining a copy
    #  of this software and associated documentation files (the "Software"), to deal
    #  in the Software without restriction, including without limitation the rights
    #  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    #  copies of the Software, and to permit persons to whom the Software is
    #  furnished to do so, subject to the following conditions:
    #
    #  The above copyright notice and this permission notice shall be included in
    #  all copies or substantial portions of the Software.
    #
    #  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    #  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    #  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    #  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    #  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    #  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
    #  THE SOFTWARE.

    # Usage jenkins-slave.sh [options] -url http://jenkins [SECRET] [AGENT_NAME]
    # Optional environment variables :
    # * JENKINS_TUNNEL : HOST:PORT for a tunnel to route TCP traffic to jenkins host, when jenkins can't be directly accessed over network
    # * JENKINS_URL : alternate jenkins URL
    # * JENKINS_SECRET : agent secret, if not set as an argument
    # * JENKINS_AGENT_NAME : agent name, if not set as an argument

    if [ $# -eq 1 ]; then

        # if `docker run` only has one arguments, we assume user is running alternate command like `bash` to inspect the image
        exec "$@"

    else

        # if -tunnel is not provided try env vars
        case "$@" in
            *"-tunnel "*) ;;
            *)
            if [ ! -z "$JENKINS_TUNNEL" ]; then
                TUNNEL="-tunnel $JENKINS_TUNNEL"
            fi ;;
        esac

        if [ -n "$JENKINS_URL" ]; then
            URL="-url $JENKINS_URL"
        fi

        if [ -n "$JENKINS_NAME" ]; then
            JENKINS_AGENT_NAME="$JENKINS_NAME"
        fi

        if [ -z "$JNLP_PROTOCOL_OPTS" ]; then
            echo "Warning: JnlpProtocol3 is disabled by default, use JNLP_PROTOCOL_OPTS to alter the behavior"
            JNLP_PROTOCOL_OPTS="-Dorg.jenkinsci.remoting.engine.JnlpProtocol3.disabled=true"
        fi

        # If both required options are defined, do not pass the parameters
        OPT_JENKINS_SECRET=""
        if [ -n "$JENKINS_SECRET" ]; then
            case "$@" in
                *"${JENKINS_SECRET}"*) echo "Warning: SECRET is defined twice in command-line arguments and the environment variable" ;;
                *)
                OPT_JENKINS_SECRET="${JENKINS_SECRET}" ;;
            esac
        fi

        OPT_JENKINS_AGENT_NAME=""
        if [ -n "$JENKINS_AGENT_NAME" ]; then
            case "$@" in
                *"${JENKINS_AGENT_NAME}"*) echo "Warning: AGENT_NAME is defined twice in command-line arguments and the environment variable" ;;
                *)
                OPT_JENKINS_AGENT_NAME="${JENKINS_AGENT_NAME}" ;;
            esac
        fi

        SLAVE_JAR=/usr/share/jenkins/slave.jar
        if [ ! -f "$SLAVE_JAR" ]; then
            tmpfile=$(mktemp)
            if hash wget > /dev/null 2>&1; then
                wget -O "$tmpfile" "$JENKINS_URL/jnlpJars/slave.jar"
            elif hash curl > /dev/null 2>&1; then
                curl -o "$tmpfile" "$JENKINS_URL/jnlpJars/slave.jar"
            else
                echo "Image does not include $SLAVE_JAR and could not find wget or curl to download it"
                return 1
            fi
            SLAVE_JAR=$tmpfile
        fi

        #TODO: Handle the case when the command-line and Environment variable contain different values.
        #It is fine it blows up for now since it should lead to an error anyway.

        exec java $JAVA_OPTS $JNLP_PROTOCOL_OPTS -cp $SLAVE_JAR hudson.remoting.jnlp.Main -headless $TUNNEL $URL $OPT_JENKINS_SECRET $OPT_JENKINS_AGENT_NAME "$@"
    fi
