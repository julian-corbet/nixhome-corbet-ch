# Asserts what the household actually RENDERS, by reading the manifests out of the rendered
# environment with a YAML parser.
#
# Why not just evaluate: a module that type-checks can still render an application whose Service
# points at a port nothing listens on, whose store is mounted somewhere the application does not
# write, or whose rolling update puts two writers on one SQLite file. None of that is an eval error.
# The first is an outage; the second is worse, because an application that finds an empty directory
# INITIALISES AN EMPTY STORE and then presents it as the household's inventory.
#
# The assertions below are the module's PROMISES rather than a transcript of its current output: the
# catalogue's own knowledge (port, mount path, probe shape and timing, the environment an
# application needs to be correct) reaches the objects; state is backed by what the consumer
# supplied and mounted where the application writes; a credential is a reference and never a value;
# the domain decides the namespace; a namespace that holds a household's records cannot be
# cascade-deleted; and no fleet address reaches any object.
{ pkgs, lib, env }:

pkgs.runCommand "nixhome-cluster-render"
{
  nativeBuildInputs = [ pkgs.yq-go ];
  manifests = env.environmentPackage;
  # Not manifests, so they cannot be asserted from the tree: the reports that say which domain each
  # workload landed in and which of them stop doing work while they sleep.
  domains = lib.concatStringsSep " "
    (lib.sort (a: b: a < b)
      (lib.mapAttrsToList (n: d: "${n}=${d}") env.config.nixhome.domains));
  dormant = lib.concatStringsSep " " (lib.sort (a: b: a < b) env.config.nixhome.dormantWhileAsleep);
} ''
  set -euo pipefail
  fail=0

  check() {
    if [ "$2" = "$3" ]; then
      echo "  ok   $1: $3"
    else
      echo "  FAIL $1: expected '$2', got '$3'"
      fail=1
    fi
  }

  present() {
    if [ -e "$2" ]; then echo "  ok   $1: rendered"; else echo "  FAIL $1: not rendered ($2)"; fail=1; fi
  }

  absent() {
    if [ -e "$2" ]; then echo "  FAIL $1: rendered but should not be ($2)"; fail=1; else echo "  ok   $1: correctly not rendered"; fi
  }

  y() { yq -r "$1" "$2"; }

  AS_D=$manifests/example-assets/Deployment-example-assets.yaml
  AS_S=$manifests/example-assets/Service-example-assets.yaml
  AS_A=$manifests/apps/Application-example-assets.yaml
  AS_NS=$manifests/example-assets/Namespace-example-belongings.yaml
  IN_D=$manifests/example-inventory/Deployment-example-inventory.yaml
  IN_S=$manifests/example-inventory/Service-example-inventory.yaml
  GR_D=$manifests/example-groceries/Deployment-example-groceries.yaml
  GR_S=$manifests/example-groceries/Service-example-groceries.yaml
  GR_A=$manifests/apps/Application-example-groceries.yaml
  GR_NS=$manifests/example-groceries/Namespace-example-housekeeping.yaml
  CH_D=$manifests/example-chores/Deployment-example-chores.yaml
  CH_S=$manifests/example-chores/Service-example-chores.yaml
  SC_D=$manifests/example-scanner/Deployment-example-scanner.yaml
  SC_S=$manifests/example-scanner/Service-example-scanner.yaml

  echo "== the whole rendered Deployment of one tracker =="
  cat $AS_D

  echo "== every workload is rendered in full by the app grammar =="
  for d in "$AS_D" "$IN_D" "$GR_D" "$CH_D" "$SC_D"; do
    present "$(basename $d)" "$d"
    check "$(basename $d) kind" "Deployment" "$(y '.kind' $d)"
  done
  for s in "$AS_S" "$IN_S" "$GR_S" "$CH_S" "$SC_S"; do
    present "$(basename $s)" "$s"
  done
  check "managed-by is the grammar's" "nixk3s" "$(y '.metadata.labels."app.kubernetes.io/managed-by"' $AS_D)"

  echo "== THE DOMAIN DECIDES THE NAMESPACE, and a companion lands beside the tracker it feeds =="
  check "asset tracker namespace"  "example-belongings"   "$(y '.metadata.namespace' $AS_D)"
  check "home inventory namespace" "example-belongings"   "$(y '.metadata.namespace' $IN_D)"
  check "household ERP namespace"  "example-housekeeping" "$(y '.metadata.namespace' $GR_D)"
  check "chore tracker namespace"  "example-housekeeping" "$(y '.metadata.namespace' $CH_D)"
  check "companion namespace"      "example-housekeeping" "$(y '.metadata.namespace' $SC_D)"
  check "the domain report" \
    "example-assets=belongings example-chores=housekeeping example-groceries=housekeeping example-inventory=belongings example-scanner=housekeeping" \
    "$domains"

  echo "== the image is the catalogue repository plus THIS declaration's version, unless pinned =="
  check "unpinned by design" "dumbwareio/dumbassets:0.0.0" \
    "$(y '.spec.template.spec.containers[0].image' $AS_D)"
  check "digest-pinned" \
    "registry.example.com/example-org/example-inventory:0.0.0@sha256:0000000000000000000000000000000000000000000000000000000000000000" \
    "$(y '.spec.template.spec.containers[0].image' $IN_D)"

  echo "== the application's own port, and a Service that targets the port the container declares =="
  check "asset tracker container port" "3000" "$(y '.spec.template.spec.containers[0].ports[0].containerPort' $AS_D)"
  check "asset tracker service port"   "3000" "$(y '.spec.ports[0].port' $AS_S)"
  check "asset tracker targetPort"     "http" "$(y '.spec.ports[0].targetPort' $AS_S)"
  check "home inventory port"          "7745" "$(y '.spec.ports[0].port' $IN_S)"
  check "household ERP port"           "80"   "$(y '.spec.ports[0].port' $GR_S)"
  check "chore tracker port"           "2021" "$(y '.spec.ports[0].port' $CH_S)"

  echo "== state: mounted where the APPLICATION writes, backed by what the consumer supplied =="
  check "mount path is the catalogue's" "/app/data" \
    "$(y '.spec.template.spec.containers[0].volumeMounts[0].mountPath' $AS_D)"
  check "backing is the declaration's"  "/example/state/assets" \
    "$(y '.spec.template.spec.volumes[0].hostPath.path' $AS_D)"
  check "a store must already exist"    "Directory" \
    "$(y '.spec.template.spec.volumes[0].hostPath.type' $AS_D)"

  echo "== two directories, one nested inside the other, and both are backed =="
  check "config mount" "/config" \
    "$(y '.spec.template.spec.containers[0].volumeMounts[] | select(.name == "config") | .mountPath' $CH_D)"
  check "data mount"   "/usr/src/app/data" \
    "$(y '.spec.template.spec.containers[0].volumeMounts[] | select(.name == "data")   | .mountPath' $CH_D)"
  check "config backing" "/example/state/chores" \
    "$(y '.spec.template.spec.volumes[] | select(.name == "config") | .hostPath.path' $CH_D)"
  check "data backing"   "/example/state/chores/database" \
    "$(y '.spec.template.spec.volumes[] | select(.name == "data")   | .hostPath.path' $CH_D)"

  echo "== a household record has a single writer: state forces Recreate, never a rolling update =="
  for d in "$AS_D" "$IN_D" "$GR_D" "$CH_D" "$SC_D"; do
    check "$(basename $d) strategy" "Recreate" "$(y '.spec.strategy.type' $d)"
  done

  echo "== node-path state pins the pod, and the objects say so =="
  check "node-pinned label" "true" "$(y '.metadata.labels."nixk3s.dev/node-pinned"' $AS_D)"
  check "nodeSelector"      "example-node" "$(y '.spec.template.spec.nodeSelector."kubernetes.io/hostname"' $AS_D)"

  echo "== a credential is a REFERENCE to a Secret and a key, and no Secret object is ever rendered =="
  check "secretKeyRef name" "example-assets" \
    "$(y '.spec.template.spec.containers[0].env[] | select(.name == "DUMBASSETS_PIN") | .valueFrom.secretKeyRef.name' $AS_D)"
  check "secretKeyRef key"  "pin" \
    "$(y '.spec.template.spec.containers[0].env[] | select(.name == "DUMBASSETS_PIN") | .valueFrom.secretKeyRef.key' $AS_D)"
  check "no literal value"  "null" \
    "$(y '.spec.template.spec.containers[0].env[] | select(.name == "DUMBASSETS_PIN") | .value' $AS_D)"
  check "the pepper is a reference too" "example-inventory" \
    "$(y '.spec.template.spec.containers[0].env[] | select(.name == "HBOX_AUTH_API_KEY_PEPPER") | .valueFrom.secretKeyRef.name' $IN_D)"
  absent "a rendered Secret object" "$manifests/example-assets/Secret-example-assets.yaml"

  echo "== the correctness environment is the catalogue's, and policy is merged over it =="
  check "the database opens with a busy timeout, WAL and foreign keys" \
    "/data/homebox.db?_pragma=busy_timeout=2000&_pragma=journal_mode=WAL&_fk=1&_time_format=sqlite" \
    "$(y '.spec.template.spec.containers[0].env[] | select(.name == "HBOX_DATABASE_SQLITE_PATH") | .value' $IN_D)"
  check "which config file the chore tracker reads" "selfhosted" \
    "$(y '.spec.template.spec.containers[0].env[] | select(.name == "DT_ENV") | .value' $CH_D)"
  check "identity numbers are POLICY and come from the declaration" "1234" \
    "$(y '.spec.template.spec.containers[0].env[] | select(.name == "PUID") | .value' $GR_D)"
  check "no resource sizing was invented for anything" "null" \
    "$(y '.spec.template.spec.containers[0].resources' $AS_D)"

  echo "== probes: the shape the application can actually answer, with its own timing =="
  check "an HTTP path that means ready" "/" \
    "$(y '.spec.template.spec.containers[0].readinessProbe.httpGet.path' $AS_D)"
  check "the inventory answers a status endpoint" "/api/v1/status" \
    "$(y '.spec.template.spec.containers[0].readinessProbe.httpGet.path' $IN_D)"
  check "the ERP has no cheap health endpoint, so it is a TCP connect" "80" \
    "$(y '.spec.template.spec.containers[0].readinessProbe.tcpSocket.port' $GR_D)"
  check "and its schema migration is waited for" "15" \
    "$(y '.spec.template.spec.containers[0].readinessProbe.initialDelaySeconds' $GR_D)"
  check "a patient first-boot budget" "24" \
    "$(y '.spec.template.spec.containers[0].readinessProbe.failureThreshold' $AS_D)"
  for d in "$AS_D" "$IN_D" "$GR_D" "$CH_D" "$SC_D"; do
    check "$(basename $d): no liveness probe was synthesized" "null" \
      "$(y '.spec.template.spec.containers[0].livenessProbe' $d)"
  done

  echo "== scale-to-zero: the replica count belongs to the wake front, and what stops is countable =="
  check "an always-on workload owns its replica count" "1" "$(y '.spec.replicas' $AS_D)"
  check "a sleeping one renders none"                 "null" "$(y '.spec.replicas' $GR_D)"
  check "and its Application ignores that field"      "/spec/replicas" \
    "$(y '.spec.ignoreDifferences[0].jsonPointers[0]' $GR_A)"
  check "the wake front is recorded as a class"       "keda" "$(y '.metadata.labels."nixk3s.dev/wake"' $GR_D)"
  check "only the workload with a scheduler is dormant while asleep" "example-chores" "$dormant"

  echo "== the namespaces a household's records live in cannot be cascade-deleted =="
  present "belongings namespace"   "$AS_NS"
  present "housekeeping namespace" "$GR_NS"
  check "belongings Prune=false"   "Prune=false" "$(y '.metadata.annotations."argocd.argoproj.io/sync-options"' $AS_NS)"
  check "housekeeping Prune=false" "Prune=false" "$(y '.metadata.annotations."argocd.argoproj.io/sync-options"' $GR_NS)"
  absent "a second creator of the belongings namespace" \
    "$manifests/example-inventory/Namespace-example-belongings.yaml"

  echo "== NO FLEET ADDRESS REACHES ANY OBJECT: a class is a label, never a number =="
  for svc in "$AS_S" "$IN_S" "$GR_S" "$CH_S" "$SC_S"; do
    check "$(basename $svc): type"           "ClusterIP" "$(y '.spec.type' $svc)"
    check "$(basename $svc): no pinned IP"   "null"      "$(y '.spec.clusterIP' $svc)"
    check "$(basename $svc): no LB address"  "null"      "$(y '.spec.loadBalancerIP' $svc)"
    check "$(basename $svc): no externalIPs" "null"      "$(y '.spec.externalIPs' $svc)"
    check "$(basename $svc): no nodePort"    "null"      "$(y '.spec.ports[0].nodePort' $svc)"
  done
  check "exposure is a class on the object" "public" "$(y '.metadata.labels."nixk3s.dev/exposure"' $AS_D)"

  echo "== every Application lands in the household's project, at the workload's own destination =="
  for app in example-assets example-inventory example-groceries example-chores example-scanner; do
    check "$app project" "example-home" "$(y '.spec.project' $manifests/apps/Application-$app.yaml)"
  done
  check "belongings destination"   "example-belongings"   "$(y '.spec.destination.namespace' $AS_A)"
  check "housekeeping destination" "example-housekeeping" "$(y '.spec.destination.namespace' $GR_A)"

  echo "== nothing is passed through untyped: no workload here has an escape hatch to use =="
  for app in example-assets example-inventory example-groceries example-chores example-scanner; do
    check "$app: no verbatim manifests" "null" \
      "$(y '.spec.source.plugin' $manifests/apps/Application-$app.yaml)"
  done

  if [ "$fail" -ne 0 ]; then
    echo "rendered output does not match the household's promises" >&2
    exit 1
  fi
  echo "all render assertions hold"
  cp -r $manifests $out
''
