import importlib.util
import json
import unittest
from pathlib import Path
from unittest import mock


MODULE_PATH = (
    Path(__file__).resolve().parents[2] / "shared" / "lib" / "codex_matrix_agent.py"
)
TEMPLATE_PATH = (
    Path(__file__).resolve().parents[1] / "configs" / "manager-openclaw.json.tmpl"
)
SPEC = importlib.util.spec_from_file_location("codex_matrix_agent", MODULE_PATH)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC and SPEC.loader
SPEC.loader.exec_module(MODULE)


class _FakeResponse:
    def __init__(self, payload):
        self._payload = payload

    def read(self):
        return json.dumps(self._payload).encode("utf-8")

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, tb):
        return False


class RouterBypassTests(unittest.TestCase):
    # 构造一个最小可用的 Agent，便于只测试路由判断逻辑。
    def _make_agent(self, role):
        agent = MODULE.HiClawCodexAgent.__new__(MODULE.HiClawCodexAgent)
        agent.role = role
        agent._router_gateway_url = "http://example.test/v1/chat/completions"
        agent._router_gateway_key = "test-key"
        agent._router_model = "gpt-5-nano"
        agent._router_timeout = 20
        agent.user_id = "@manager:test"
        agent.localpart = "@manager"
        return agent

    def test_manager_group_room_bypasses_router(self):
        agent = self._make_agent("manager")
        events = [
            {
                "sender": "@alice:test",
                "content": {"msgtype": "m.text", "body": "status update"},
            }
        ]

        with mock.patch.object(
            MODULE.urlrequest,
            "urlopen",
            side_effect=AssertionError("router should not be called"),
        ):
            self.assertTrue(agent._router_should_reply("!room:test", "group", events))

    def test_worker_group_room_still_uses_router(self):
        agent = self._make_agent("worker")
        events = [
            {
                "sender": "@alice:test",
                "content": {"msgtype": "m.text", "body": "thanks"},
            }
        ]

        with mock.patch.object(
            MODULE.urlrequest,
            "urlopen",
            return_value=_FakeResponse(
                {"choices": [{"message": {"content": "NO"}}]}
            ),
        ) as mocked_urlopen:
            self.assertFalse(agent._router_should_reply("!room:test", "group", events))

        mocked_urlopen.assert_called_once()


class HeartbeatSchedulingTests(unittest.TestCase):
    # 构造一个只包含 heartbeat 调度所需字段的 Agent，避免依赖完整初始化流程。
    def _make_agent(self):
        agent = MODULE.HiClawCodexAgent.__new__(MODULE.HiClawCodexAgent)
        agent.role = "manager"
        agent.runner = mock.Mock()
        agent.heartbeat_enabled = True
        agent.heartbeat_every_seconds = 1200
        agent.heartbeat_prompt = "Read ~/HEARTBEAT.md and follow the checklist."
        agent.heartbeat_next_at = 100.0
        agent.heartbeat_thread_id = None
        return agent

    def test_due_heartbeat_runs_turn_without_room_message(self):
        agent = self._make_agent()
        agent.runner.run_turn.return_value = MODULE.CodexRunResult(
            "heartbeat-thread",
            "HEARTBEAT_OK",
        )

        ran = agent._maybe_run_heartbeat(now=100.0)

        self.assertTrue(ran)
        agent.runner.run_turn.assert_called_once_with(agent.heartbeat_prompt, None)
        self.assertEqual(agent.heartbeat_thread_id, "heartbeat-thread")
        self.assertEqual(agent.heartbeat_next_at, 1300.0)

    def test_heartbeat_not_due_does_not_run(self):
        agent = self._make_agent()
        agent.heartbeat_next_at = 101.0

        ran = agent._maybe_run_heartbeat(now=100.0)

        self.assertFalse(ran)
        agent.runner.run_turn.assert_not_called()
        self.assertEqual(agent.heartbeat_next_at, 101.0)


class ManagerConfigTemplateTests(unittest.TestCase):
    # 直接校验模板默认值，避免 heartbeat 周期被无意改回过长配置。
    def test_manager_default_heartbeat_interval_is_five_minutes(self):
        template = TEMPLATE_PATH.read_text(encoding="utf-8")

        self.assertIn('"heartbeat": {', template)
        self.assertIn('"every": "5m"', template)


class RunLoopHeartbeatTests(unittest.TestCase):
    # 构造一个最小的主循环 Agent，只保留 run_forever() 依赖的字段和方法。
    def _make_agent(self):
        agent = MODULE.HiClawCodexAgent.__new__(MODULE.HiClawCodexAgent)
        agent.state = {}
        agent.matrix = mock.Mock()
        agent._reload_config = mock.Mock()
        agent._ensure_expected_room_joined = mock.Mock()
        agent._ensure_ready_file = mock.Mock()
        agent._save_state = mock.Mock()
        agent.process_room = mock.Mock()
        agent._maybe_run_heartbeat = mock.Mock()
        return agent

    def test_run_forever_triggers_heartbeat_without_new_messages(self):
        # 即使 sync 没有任何新 timeline，主循环也必须检查 heartbeat 调度。
        agent = self._make_agent()
        agent.matrix.sync.side_effect = [
            {"next_batch": "catchup", "rooms": {"join": {}}},
            {"next_batch": "loop-1", "rooms": {"join": {}}},
            KeyboardInterrupt(),
        ]

        with self.assertRaises(KeyboardInterrupt):
            agent.run_forever()

        agent.process_room.assert_not_called()
        agent._maybe_run_heartbeat.assert_called_once_with()
        self.assertEqual(agent.state["since"], "loop-1")

    def test_run_forever_calls_heartbeat_after_room_processing(self):
        # room turn 与 heartbeat 必须串行执行，heartbeat 只能排在房间处理之后。
        agent = self._make_agent()
        events = [
            {
                "type": "m.room.message",
                "sender": "@alice:test",
                "origin_server_ts": 1,
                "content": {"msgtype": "m.text", "body": "status"},
            }
        ]
        order = []
        agent.process_room.side_effect = lambda room_id, timeline: order.append(
            f"room:{room_id}:{len(timeline)}"
        )
        agent._maybe_run_heartbeat.side_effect = lambda: order.append("heartbeat")
        agent.matrix.sync.side_effect = [
            {"next_batch": "catchup", "rooms": {"join": {}}},
            {
                "next_batch": "loop-1",
                "rooms": {"join": {"!room:test": {"timeline": {"events": events}}}},
            },
            KeyboardInterrupt(),
        ]

        with self.assertRaises(KeyboardInterrupt):
            agent.run_forever()

        self.assertEqual(order, ["room:!room:test:1", "heartbeat"])
