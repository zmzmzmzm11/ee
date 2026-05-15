#!/usr/bin/env python
"""
Suricata EVE JSON 模拟器
持续生成模拟的 Suricata 网络流量事件，写入 eve.json 文件。
支持多种事件类型：alert, dns, http, tls, dhcp, flow, ssh
"""
import json
import time
import random
import os
import signal
import sys
from datetime import datetime, timezone, timedelta

CST = timezone(timedelta(hours=8))

# 模拟网络资产
INTERNAL_IPS = ["192.168.1.100", "192.168.1.101", "192.168.1.102", "192.168.1.50",
                "192.168.1.200", "10.0.0.50", "172.16.0.55"]
EXTERNAL_IPS = ["10.10.10.20", "185.130.5.200", "23.215.133.90",
                "93.184.216.34", "104.16.124.96", "13.107.42.14",
                "8.8.8.8", "1.1.1.1", "142.250.80.4"]
SERVERS = ["192.168.1.10", "192.168.1.20", "10.0.0.50"]
SENSOR = "suricata-sensor-01"

# 模拟告警规则库
ALERT_RULES = [
    {"gid": 1, "signature_id": 2001219, "rev": 4, "signature": "ET EXPLOIT Apache Struts2 Remote Code Execution Attempt", "category": "attempted-admin", "severity": 1},
    {"gid": 1, "signature_id": 2023401, "rev": 2, "signature": "ET MALWARE WannaCry Ransomware Propagation SMB", "category": "malware", "severity": 1},
    {"gid": 1, "signature_id": 2010935, "rev": 3, "signature": "ET TROJAN Cobalt Strike Beacon Activity", "category": "trojan-activity", "severity": 1},
    {"gid": 1, "signature_id": 2014728, "rev": 2, "signature": "ET POLICY DNS Query to Suspicious TLD", "category": "policy-violation", "severity": 2},
    {"gid": 1, "signature_id": 2028923, "rev": 1, "signature": "ET INFO Suspicious PowerShell User-Agent Detected", "category": "potentially-bad", "severity": 2},
    {"gid": 1, "signature_id": 2021096, "rev": 2, "signature": "ET SCAN SSH Brute Force Login Attempt", "category": "scan", "severity": 2},
    {"gid": 1, "signature_id": 2008473, "rev": 3, "signature": "ET EXPLOIT MySQL Brute Force Login Attempt", "category": "attempted-admin", "severity": 1},
    {"gid": 1, "signature_id": 2019194, "rev": 2, "signature": "ET SCAN RDP Connection Attempt Detected", "category": "scan", "severity": 2},
    {"gid": 1, "signature_id": 2017497, "rev": 1, "signature": "ET POLICY TLS SNI Contains Suspicious Domain", "category": "policy-violation", "severity": 2},
]

DNS_QUERIES = [
    ("www.google.com", "A"), ("github.com", "AAAA"), ("api.example.com", "A"),
    ("login.microsoftonline.com", "A"), ("cdn.cloudflare.com", "A"),
    ("malware-c2.evil.com", "A"), ("phishing-login.tk", "A"),
    ("outlook.office.com", "AAAA"), ("www.baidu.com", "A"),
    ("s3.amazonaws.com", "A"), ("discord.com", "AAAA"),
]

TLS_SNIS = [
    ("cloudflare.com", "TLS 1.3", "t13d1516h2_8daaf6152771_b1ff8a2e2d17"),
    ("evil.local", "TLS 1.2", "t13d1516h2_8daaf6152771_e5627efa2ab1"),
    ("outlook.office.com", "TLS 1.2", "t12d1108h2_ea7f7b4a7a3e_bc4f3b2a1d0e"),
    ("login.phishing.tk", "TLS 1.2", "t12d1108h2_ea7f7b4a7a3e_e5627efa2ab1"),
]

HTTP_PATHS = [
    ("example.com", "/index.html", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"),
    ("malware-drop.example.com", "/payload.bin", "Mozilla/5.0 (Windows NT; Windows NT 10.0; en-US) WindowsPowerShell/5.1"),
    ("api.github.com", "/repos/evebox/evebox/releases", "curl/7.88.1"),
]

flow_id_counter = 1000

def ts():
    return datetime.now(CST).strftime("%Y-%m-%dT%H:%M:%S.%f+0800")

def make_flow(pkts_s, pkts_c, bytes_s, bytes_c, state="closed"):
    return {
        "pkts_toserver": pkts_s, "pkts_toclient": pkts_c,
        "bytes_toserver": bytes_s, "bytes_toclient": bytes_c,
        "start": ts(), "end": ts(), "age": 0, "state": state, "reason": "timeout"
    }

def gen_alert():
    global flow_id_counter
    flow_id_counter += 1
    rule = random.choice(ALERT_RULES)
    src = random.choice(INTERNAL_IPS)
    dst = random.choice(SERVERS if random.random() > 0.5 else EXTERNAL_IPS)
    src_port = random.randint(49152, 65535)
    dst_port = random.choice([80, 443, 22, 3306, 3389, 445, 8080, 53])
    event = {
        "timestamp": ts(), "flow_id": flow_id_counter,
        "in_iface": "eth0", "event_type": "alert",
        "src_ip": src, "src_port": src_port,
        "dest_ip": dst, "dest_port": dst_port,
        "proto": "TCP" if dst_port != 53 else "UDP",
        "host": SENSOR,
        "alert": rule,
        "flow": make_flow(random.randint(3, 20), random.randint(2, 15),
                         random.randint(500, 5000), random.randint(300, 15000),
                         random.choice(["closed", "established"])),
    }
    # 偶尔附加 TLS 信息
    if dst_port == 443 and random.random() > 0.4:
        tls_info = random.choice(TLS_SNIS)
        event["tls"] = {
            "subject": f"CN=*.{tls_info[0]}", "issuerdn": "CN=Let's Encrypt",
            "serial": hex(random.randint(0, 0xFFFFFFFF))[2:],
            "fingerprint": ":".join([f"{random.randint(0,255):02x}" for _ in range(16)]),
            "sni": tls_info[0], "version": tls_info[1], "ja4": tls_info[2],
            "notbefore": "2026-01-01T00:00:00Z", "notafter": "2027-01-01T23:59:59Z",
        }
    # 偶尔附加 DNS 信息
    if dst_port == 53 and random.random() > 0.5:
        dns_q = random.choice(DNS_QUERIES)
        event["dns"] = {"type": "query", "id": random.randint(1, 65535),
                       "rrname": dns_q[0], "rrtype": dns_q[1], "tx_id": random.randint(1, 65535)}
    return event

def gen_dns():
    global flow_id_counter
    flow_id_counter += 1
    dns_q = random.choice(DNS_QUERIES)
    src = random.choice(INTERNAL_IPS)
    # Query
    yield {
        "timestamp": ts(), "flow_id": flow_id_counter,
        "in_iface": "eth0", "event_type": "dns",
        "src_ip": src, "src_port": random.randint(49152, 65535),
        "dest_ip": "8.8.8.8", "dest_port": 53,
        "proto": "UDP", "host": SENSOR,
        "dns": {"type": "query", "id": random.randint(1, 65535),
                "rrname": dns_q[0], "rrtype": dns_q[1], "tx_id": random.randint(1, 65535)}
    }
    # Answer
    if random.random() > 0.2:
        yield {
            "timestamp": ts(), "flow_id": flow_id_counter,
            "in_iface": "eth0", "event_type": "dns",
            "src_ip": "8.8.8.8", "src_port": 53,
            "dest_ip": src, "dest_port": random.randint(49152, 65535),
            "proto": "UDP", "host": SENSOR,
            "dns": {"type": "answer", "id": random.randint(1, 65535),
                    "rrname": dns_q[0], "rrtype": dns_q[1], "tx_id": random.randint(1, 65535),
                    "rcode": "NOERROR",
                    "answers": [{"rrname": dns_q[0], "rrtype": dns_q[1],
                                "ttl": random.randint(60, 86400),
                                "rdata": f"{random.randint(1,255)}.{random.randint(0,255)}.{random.randint(0,255)}.{random.randint(1,254)}"}]
                    }
        }

def gen_http():
    global flow_id_counter
    flow_id_counter += 1
    http_info = random.choice(HTTP_PATHS)
    src = random.choice(INTERNAL_IPS)
    return {
        "timestamp": ts(), "flow_id": flow_id_counter,
        "in_iface": "eth0", "event_type": "http",
        "src_ip": src, "src_port": random.randint(49152, 65535),
        "dest_ip": random.choice(EXTERNAL_IPS), "dest_port": 80,
        "proto": "TCP", "host": SENSOR,
        "http": {"hostname": http_info[0], "url": http_info[1],
                 "http_user_agent": http_info[2],
                 "http_method": "GET", "length": random.randint(0, 10000),
                 "status": random.choice([200, 200, 200, 301, 404, 500]),
                 "protocol": "HTTP/1.1"},
        "flow": make_flow(random.randint(3, 10), random.randint(2, 8),
                         random.randint(400, 3000), random.randint(200, 20000)),
    }

def gen_tls():
    global flow_id_counter
    flow_id_counter += 1
    tls_info = random.choice(TLS_SNIS)
    src = random.choice(INTERNAL_IPS)
    return {
        "timestamp": ts(), "flow_id": flow_id_counter,
        "in_iface": "eth0", "event_type": "tls",
        "src_ip": src, "src_port": random.randint(49152, 65535),
        "dest_ip": random.choice(EXTERNAL_IPS), "dest_port": 443,
        "proto": "TCP", "host": SENSOR,
        "tls": {"subject": f"CN=*.{tls_info[0]}", "issuerdn": "CN=DigiCert",
                "serial": hex(random.randint(0, 0xFFFFFFFF))[2:],
                "fingerprint": ":".join([f"{random.randint(0,255):02x}" for _ in range(16)]),
                "sni": tls_info[0], "version": tls_info[1], "ja4": tls_info[2],
                "notbefore": "2026-01-01T00:00:00Z", "notafter": "2027-01-01T23:59:59Z"},
    }

def main():
    output_file = os.environ.get("EVE_OUTPUT", "suricata-eve.json")
    interval = float(os.environ.get("EVE_INTERVAL", "2.0"))
    print(f"[Suricata Simulator] Writing to {output_file}, interval={interval}s")
    print(f"[Suricata Simulator] Sensor: {SENSOR}")
    print(f"[Suricata Simulator] Press Ctrl+C to stop")

    count = 0
    try:
        with open(output_file, "a", buffering=1) as f:
            while True:
                r = random.random()
                if r < 0.35:
                    event = gen_alert()
                elif r < 0.55:
                    for evt in gen_dns():
                        f.write(json.dumps(evt, ensure_ascii=False) + "\n")
                        count += 1
                    time.sleep(0.1)
                    continue
                elif r < 0.75:
                    event = gen_http()
                else:
                    event = gen_tls()

                f.write(json.dumps(event, ensure_ascii=False) + "\n")
                f.flush()
                count += 1

                if count % 10 == 0:
                    print(f"[{ts()}] Generated {count} events total")

                time.sleep(interval + random.uniform(-0.5, 0.5))
    except KeyboardInterrupt:
        print(f"\n[Suricata Simulator] Stopped. Total events: {count}")
        sys.exit(0)

if __name__ == "__main__":
    main()
