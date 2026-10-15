from pathlib import Path

from deepseek_harness import DeepSeekHarness, HarnessClient, HarnessConfig
from deepseek_harness.api import DeepSeekHarnessConfig


def test_clean_high_level_defaults(monkeypatch) -> None:
    monkeypatch.delenv("DSH_LOCAL_MODEL_NAME", raising=False)
    config = DeepSeekHarnessConfig()
    assert config.provider == "local-offline"
    assert config.model == "qwen3:0.6b"
    monkeypatch.setenv("DSH_LOCAL_MODEL_NAME", "my-local-model")
    assert DeepSeekHarnessConfig().model == "my-local-model"


def test_javascript_cli_uses_explicit_node(tmp_path: Path) -> None:
    entry = tmp_path / "bin.js"
    entry.write_text("// not executed by this test")
    node = tmp_path / "node.exe"
    node.write_text("not executed by this test")
    client = HarnessClient(HarnessConfig(dsh_bin=str(entry), dsh_home=str(tmp_path / "home")))
    env = {"DSH_NODE_BINARY": str(node)}
    assert client._default_launch_args(env) == (str(node.resolve()), str(entry.resolve()), "--profile", "sdk")


def test_high_level_key_and_endpoint_target_local_backend(tmp_path: Path) -> None:
    harness = DeepSeekHarness(dsh_home=str(tmp_path / "home"), base_url="http://127.0.0.1:11434/v1", api_key="synthetic-local-key")
    assert harness.client.config.env["DSH_LOCAL_MODEL_BASE_URL"] == "http://127.0.0.1:11434/v1"
    assert harness.client.config.env["LOCAL_MODEL_API_KEY"] == "synthetic-local-key"
    assert "DEEPSEEK_API_KEY" not in harness.client.config.env
