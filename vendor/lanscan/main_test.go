package main

import (
	"encoding/json"
	"reflect"
	"testing"
)

func TestParsePortRange(t *testing.T) {
	from, to, err := parsePortRange("1-1024")
	if err != nil || from != 1 || to != 1024 {
		t.Fatalf("parsePortRange(1-1024) = %d,%d,%v", from, to, err)
	}
	for _, bad := range []string{"80", "0-70000", "1000-100", "x-y", ""} {
		if _, _, err := parsePortRange(bad); err == nil {
			t.Errorf("parsePortRange(%q) accepted, want error", bad)
		}
	}
}

func TestSamplePorts(t *testing.T) {
	if got := samplePorts(20, 25, 20); !reflect.DeepEqual(got, []int{20, 21, 22, 23, 24, 25}) {
		t.Errorf("samplePorts small range = %v", got)
	}
	got := samplePorts(1, 1024, 20)
	if len(got) == 0 || len(got) > 21 {
		t.Fatalf("samplePorts(1,1024,20) len = %d", len(got))
	}
	if got[0] != 1 || got[len(got)-1] != 1024 {
		t.Errorf("samplePorts endpoints = %d..%d, want 1..1024", got[0], got[len(got)-1])
	}
}

func TestHostsInCIDR(t *testing.T) {
	hosts, err := hostsInCIDR("192.168.1.0/30")
	if err != nil {
		t.Fatal(err)
	}
	want := []string{"192.168.1.0", "192.168.1.1", "192.168.1.2", "192.168.1.3"}
	if !reflect.DeepEqual(hosts, want) {
		t.Errorf("hostsInCIDR(/30) = %v, want %v", hosts, want)
	}
	if _, err := hostsInCIDR("nope"); err == nil {
		t.Error("hostsInCIDR(nope) accepted, want error")
	}
}

func TestScanReportJSON(t *testing.T) {
	out, err := json.Marshal(scanReport{
		Target:     "10.0.0.0/30",
		Ports:      "1-1024",
		StartedAt:  "2026-08-31T10:00:00Z",
		FinishedAt: "2026-08-31T10:00:01Z",
		HostsAlive: 1,
		Hosts: []hostReport{
			{IP: "10.0.0.1", MAC: "aa:bb:cc:dd:ee:ff", OpenPorts: []int{22, 80}},
			{IP: "10.0.0.2", OpenPorts: []int{}},
		},
	})
	if err != nil {
		t.Fatal(err)
	}

	var back map[string]any
	if err := json.Unmarshal(out, &back); err != nil {
		t.Fatal(err)
	}
	for _, key := range []string{"target", "ports", "started_at", "finished_at", "hosts_alive", "hosts"} {
		if _, ok := back[key]; !ok {
			t.Errorf("scanReport JSON missing key %q: %s", key, out)
		}
	}

	hosts := back["hosts"].([]any)
	h0 := hosts[0].(map[string]any)
	if h0["ip"] != "10.0.0.1" || h0["mac"] != "aa:bb:cc:dd:ee:ff" {
		t.Errorf("host[0] = %v", h0)
	}
	// mac is omitempty: absent when unknown.
	if _, ok := hosts[1].(map[string]any)["mac"]; ok {
		t.Errorf("host[1] should omit mac: %v", hosts[1])
	}
}
