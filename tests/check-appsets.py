"""Render the workshop's grouped ApplicationSets with Helm and PyYAML."""

import subprocess
from pathlib import Path

import yaml


ROOT = Path(__file__).resolve().parents[1]
REPO = "{{ .metadata.annotations.repo_url }}"
REVISION = '{{ default "HEAD" (index .metadata.annotations "repo_revision") }}'
GROUP = '{{ trimSuffix ".yaml" .path.filename }}'
POLICY = {"applicationsSync": "create-update", "preserveResourcesOnDeletion": True}
HUB_SELECTOR = {"matchLabels": {"fleet_member": "hub-cluster"}}
APPLICATIONS = {
    "addons": {
        "hub-external-secrets": "{{ .name }}-external-secrets",
        "hub-openbao": "{{ .name }}-openbao",
    },
    "agents": {
        "agent-registration": "{{ .name }}-agent",
        "spoke-controller": "{{ .name }}-controller",
        "spoke-runtime": "{{ .name }}-runtime",
        "spoke-teams": "{{ .name }}-teams",
    },
    "fleet": {"cluster-registration": GROUP + "-cluster"},
}
UPSTREAM_VERSIONS = {"external-secrets": "2.15.0", "openbao": "0.30.7"}


def check_group_installer():
    installer = yaml.safe_load((ROOT / "bootstrap/groups.yaml").read_text())["spec"]
    assert installer["goTemplate"] and installer["goTemplateOptions"] == ["missingkey=error"]
    assert installer["syncPolicy"] == POLICY
    clusters, git = installer["generators"][0]["matrix"]["generators"]
    assert clusters == {"clusters": {"selector": HUB_SELECTOR}}
    assert git["git"]["repoURL"] == REPO and git["git"]["revision"] == REVISION
    template = installer["template"]
    assert template["metadata"]["name"] == "{{ .name }}-" + GROUP
    values, chart = template["spec"]["sources"]
    assert values == {"repoURL": REPO, "targetRevision": REVISION, "ref": "values"}
    assert chart["repoURL"] == REPO and chart["targetRevision"] == REVISION
    assert chart["helm"]["releaseName"] == GROUP
    assert chart["helm"]["valueFiles"] == ["$values/{{ .path.path }}/{{ .path.filename }}"]
    assert chart["helm"]["valuesObject"] == {"group": GROUP, "revision": REVISION}
    assert template["spec"]["destination"] == {"name": "{{ .name }}", "namespace": "hga-hub-agent"}
    assert template["spec"]["syncPolicy"]["automated"]["prune"] is False
    return chart["path"], git["git"]["files"][0]["path"]


def check_rendered_groups(chart, pattern, revision=None):
    groups = sorted(ROOT.glob(pattern))
    assert {group.stem for group in groups} == APPLICATIONS.keys()
    for group in groups:
        args = ["helm", "template", group.stem, chart, "-f", str(group), "--set-string", f"group={group.stem}"]
        if revision:
            args += ["--set-string", f"revision={revision}"]
        output = subprocess.check_output(args, cwd=ROOT, text=True)
        names = {}
        for appset in yaml.safe_load_all(output):
            name = appset["metadata"]["name"]
            assert appset["kind"] == "ApplicationSet" and name not in names, name
            spec = appset["spec"]
            assert spec["goTemplate"] and spec["goTemplateOptions"] == ["missingkey=error"], name
            assert spec["syncPolicy"] == POLICY, name
            assert appset["metadata"]["labels"]["group"] == group.stem, name
            metadata = spec["template"]["metadata"]
            assert metadata["labels"]["group"] == group.stem, name
            names[name] = metadata["name"]
            application = spec["template"]["spec"]
            assert application["syncPolicy"]["automated"] == {"selfHeal": True, "prune": False}, name
            for source in application["sources"]:
                if "chart" in source:
                    assert source["targetRevision"] == UPSTREAM_VERSIONS[source["chart"]], name
                else:
                    assert source["repoURL"] == REPO and source["targetRevision"] == (revision or "HEAD"), name
                    if "path" in source and "helm" in source:
                        assert (ROOT / source["path"] / "Chart.yaml").is_file(), source["path"]
            if name == "cluster-registration":
                git = spec["generators"][0]["matrix"]["generators"][1]["git"]
                assert git["files"] == [{"path": "fleet-members/*.yaml"}]
                assert git["revision"] == (revision or "HEAD")
        assert names == APPLICATIONS[group.stem], group.stem


if __name__ == "__main__":
    chart, pattern = check_group_installer()
    for revision in (None, "workshop-appsets-groups"):
        check_rendered_groups(chart, pattern, revision)
        print(f"Checked seven workload ApplicationSets at {revision or 'HEAD'}")
