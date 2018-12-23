data "template_file" "llibicpep_job" {
  template = "${file("${path.module}/templates/github_org_job.xml.tpl")}"

  vars {
    org = "llibicpep"
  }
}

locals {
  jenkins_plugins = [
    "kubernetes:1.14.0",
    "workflow-job:2.31",
    "workflow-aggregator:2.6",
    "credentials-binding:1.17",
    "git:3.9.1",
    "github-organization-folder:1.6",
  ]

  credentials = <<CREDENTIALS
      import jenkins.model.Jenkins
      import com.cloudbees.plugins.credentials.impl.*
      import com.cloudbees.plugins.credentials.*
      import com.cloudbees.plugins.credentials.domains.*
      def c = new UsernamePasswordCredentialsImpl(CredentialsScope.GLOBAL, "github_token", "", "", "${var.github_token}")
      SystemCredentialsProvider.getInstance().getStore().addCredentials(Domain.global(), c)
      Jenkins.getInstance().save()
CREDENTIALS

  values = <<VALUES
Master:
  ImageTag: "${var.jenkins_version}-alpine"
  AdminPassword: "${random_string.password.result}"
  ServiceType: ClusterIP
  HostName: "${var.ingress_lb}"
  Ingress:
    Path: "/"
  InstallPlugins: ["${join("\",\"", local.jenkins_plugins)}"]
  InitScripts:
    00credentials: |-
${local.credentials}
  Jobs:
    llibicpep: |-
${data.template_file.llibicpep_job.rendered}
rbac:
  install: true
VALUES
}

resource "null_resource" "tiller" {
  provisioner "local-exec" {
    command = "echo ${var.tiller_dependency_id}"
  }
}

resource "kubernetes_namespace" "jenkins" {
  depends_on = ["null_resource.tiller"]

  metadata {
    name = "jenkins"
  }
}

resource "kubernetes_cluster_role_binding" "jenkins" {
  depends_on = ["kubernetes_namespace.jenkins"]

  metadata {
    name = "jenkins"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }

  subject {
    api_group = ""
    kind      = "ServiceAccount"
    name      = "default"
    namespace = "jenkins"
  }
}

resource "helm_release" "jenkins" {
  depends_on = ["kubernetes_namespace.jenkins"]

  name          = "jenkins"
  repository    = "stable"
  chart         = "jenkins"
  version       = "${var.chart_version}"
  namespace     = "jenkins"
  force_update  = "true"
  recreate_pods = "true"
  reuse         = "false"
  values        = ["${list(local.values)}"]
}
