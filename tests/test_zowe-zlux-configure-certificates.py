import os
import subprocess
import shutil
import json


def test_script_replaces_correctly():
    if not os.path.exists("tmp/zlux-example-server/config"):
        os.makedirs("tmp/zlux-example-server/config")
    shutil.copy("tests/data/zluxserver.json",
                "tmp/zlux-example-server/config/zluxserver.json")

    env = {
        "LOG_FILE": os.path.join(os.getcwd(), "tmp", "test.log"),
        "ZOWE_ROOT_DIR": os.path.join(os.getcwd(), "tmp"),
        "TEMP_DIR": os.path.join(os.getcwd(), "tmp")
    }
    print(os.getcwd())
    with open(env["LOG_FILE"], "w") as f:
        f.write("Log:\n")

    result = subprocess.run("bash scripts/zowe-zlux-configure-certificates.sh",
                            shell=True, capture_output=True, encoding="utf8", env=env)
    print(result.stdout)
    print(result.stderr)

    assert result.returncode == 0
    assert result.stdout.strip() == ""
    assert result.stderr.strip() == ""

    with open(os.path.join(env["TEMP_DIR"], "zlux-example-server", "config", "zluxserver.json")) as json_data:
        lines = []
        for line in json_data.readlines():
            if not line.strip().startswith("//"):
                lines.append(line)
        j = json.loads("".join(lines))

    assert j["node"]["https"]["keys"] \
        == [env["ZOWE_ROOT_DIR"] + "/api-mediation/keystore/localhost/localhost.keystore.key"]
    assert j["node"]["https"]["certificates"] \
        == [env["ZOWE_ROOT_DIR"] + "/api-mediation/keystore/localhost/localhost.keystore.cer"]
    assert j["node"]["https"]["certificateAuthorities"] \
        == [env["ZOWE_ROOT_DIR"] + "/api-mediation/keystore/local_ca/localca.cer"]
