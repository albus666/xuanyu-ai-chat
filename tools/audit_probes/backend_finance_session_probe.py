"""Explicit diagnostic probes, NOT regression acceptance tests.

Passing means the observed defect still exists. Reads selected function ASTs from
the supplied backend checkout. Does not import Django, load settings, connect to
databases/Redis, contact payment channels, or print session tokens.
"""

import __future__
import ast
import copy
import json
import logging
import sys
import threading
import time
import unittest
import uuid
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from decimal import Decimal, ROUND_HALF_UP
from pathlib import Path
from types import SimpleNamespace


BACKEND = Path(sys.argv.pop(1)).resolve()


def functions(relative_path, names, globals_):
    path = BACKEND / relative_path
    tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
    selected = [node for node in tree.body
                if isinstance(node, ast.FunctionDef) and node.name in names]
    assert {node.name for node in selected} == set(names)
    for node in selected:
        node.decorator_list = []
    module = ast.Module(body=selected, type_ignores=[])
    exec(compile(module, str(path), "exec",
                 flags=__future__.annotations.compiler_flag), globals_)
    return globals_


class FinanceCursor:
    """Only recognizes the exact SQL paths these probes exercise."""

    def __init__(self, status="paid"):
        self.status = status
        self.balance = Decimal("100")
        self.credited = Decimal("0")
        self.debited = Decimal("0")
        self.logs = 0
        self.result = None
        self.rowcount = 1

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False

    def execute(self, sql, args):
        sql = " ".join(sql.split())
        self.result = None
        if sql.startswith("SELECT id, user_id, amount, status, type, extra_json"):
            self.result = (1, 77, Decimal("50"), self.status, "recharge", "{}")
        elif sql.startswith("SELECT id, user_id, amount, status, type, pay_channel"):
            self.result = (1, 77, Decimal("50"), self.status, "recharge",
                           "wechat", "synthetic-trade", "{}")
        elif sql.startswith("SELECT order_no FROM order_main"):
            self.result = None
        elif sql.startswith("UPDATE order_main SET status = 'paid'"):
            self.status = "paid"
        elif sql.startswith("INSERT INTO user_wallet"):
            self.credited += args[1]
            self.balance += args[1]
        elif sql.startswith("SELECT balance, frozen_amount FROM user_wallet"):
            self.result = (self.balance, Decimal("0"))
        elif sql.startswith("UPDATE user_wallet SET balance=balance-%s"):
            self.debited += args[0]
            self.balance -= args[0]
        elif sql.startswith("UPDATE order_main SET status=%s, extra_json=%s"):
            self.status = args[0]
        elif sql.startswith("INSERT INTO wallet_log"):
            self.logs += 1
        else:
            raise AssertionError(f"Unexpected SQL in offline probe: {sql}")

    def fetchone(self):
        return self.result


def finance_namespace(cursor):
    return {
        "connection": SimpleNamespace(cursor=lambda: cursor),
        "transaction": SimpleNamespace(set_rollback=lambda value: None),
        "Decimal": Decimal,
        "ROUND_HALF_UP": ROUND_HALF_UP,
        "json": json,
        "time": time,
        "logger": logging.getLogger("offline-audit"),
    }


class Cache:
    def __init__(self):
        self.data = {}
        self.lock = threading.Lock()
        self.barrier = threading.Barrier(2)
        self.race_enabled = True

    def get(self, key):
        with self.lock:
            value = copy.deepcopy(self.data.get(key))
        # Force both logins to read the same original index before either writes.
        if self.race_enabled and key == "user_sessions:77":
            self.barrier.wait(timeout=5)
        return value

    def set(self, key, value, timeout=None):
        with self.lock:
            self.data[key] = copy.deepcopy(value)

    def delete(self, key):
        with self.lock:
            self.data.pop(key, None)


class DefectObservations(unittest.TestCase):
    def replay(self, original_status):
        cursor = FinanceCursor(original_status)
        ns = functions("apps/account/pay_views.py", ["_on_payment_success"],
                       finance_namespace(cursor))
        result = ns["_on_payment_success"](
            "synthetic-order", "wechat", "synthetic-trade", Decimal("50"))
        self.assertTrue(result)
        return cursor

    def test_control_paid_callback_does_not_credit_again(self):
        cursor = self.replay("paid")
        self.assertEqual(cursor.credited, Decimal("0"))
        self.assertEqual(cursor.logs, 0)

    def test_repro_refunded_order_is_credited_again(self):
        cursor = self.replay("refunded")
        self.assertEqual(cursor.credited, Decimal("50"))
        self.assertEqual(cursor.status, "paid")
        self.assertEqual(cursor.logs, 1)

    def test_repro_partial_refund_order_is_credited_again(self):
        cursor = self.replay("partial_refunded")
        self.assertEqual(cursor.credited, Decimal("50"))
        self.assertEqual(cursor.status, "paid")
        self.assertEqual(cursor.logs, 1)

    def test_repro_processing_refund_is_marked_finished(self):
        cursor = FinanceCursor()
        ns = finance_namespace(cursor)
        ns["payment"] = SimpleNamespace(
            refund_channel_order=lambda **kwargs: {"status": "PROCESSING"})
        functions("apps/account/refund_service.py",
                  ["_d", "_money", "process_order_refund"], ns)
        result, error = ns["process_order_refund"](order_no="synthetic-order")
        self.assertIsNone(error)
        self.assertEqual(result["channel"]["status"], "PROCESSING")
        self.assertEqual(result["status"], "refunded")
        self.assertEqual(cursor.status, "refunded")
        self.assertEqual(cursor.debited, Decimal("50"))

    def test_repro_concurrent_sessions_escape_revoke_all(self):
        cache = Cache()
        ns = functions("apps/account/session_store.py", [
            "_now_iso", "_forget_token", "create_session",
            "get_user_id_by_token", "remove_all_user_sessions",
        ], {
            "cache": cache, "uuid": uuid, "datetime": datetime,
            "timezone": timezone, "TTL": 600,
            "SESSION_PREFIX": "session:",
            "SESSION_ACTIVITY_PREFIX": "session_activity:",
            "USER_SESSIONS_PREFIX": "user_sessions:",
            "KICKED_PREFIX": "session_kicked:",
        })
        with ThreadPoolExecutor(max_workers=2) as pool:
            tasks = [pool.submit(ns["create_session"], 77) for _ in range(2)]
            sessions = [task.result(timeout=10) for task in tasks]
        cache.race_enabled = False
        self.assertEqual(sum(ns["get_user_id_by_token"](s) == 77
                             for s in sessions), 2)
        self.assertEqual(len(cache.get("user_sessions:77")), 1)
        ns["remove_all_user_sessions"](77)
        self.assertEqual(sum(ns["get_user_id_by_token"](s) == 77
                             for s in sessions), 1)


if __name__ == "__main__":
    unittest.main(verbosity=2)
