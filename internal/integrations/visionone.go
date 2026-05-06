package integrations

import (
	"bytes"
	"crypto/tls"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"github.com/swissmakers/fail2ban-ui/internal/config"
)

type visionOneIntegration struct{}

// Vision One regional base URLs.
var visionOneRegions = map[string]string{
	"us": "https://api.xdr.trendmicro.com",
	"eu": "https://api.eu.xdr.trendmicro.com",
	"jp": "https://api.xdr.trendmicro.co.jp",
	"sg": "https://api.sg.xdr.trendmicro.com",
	"in": "https://api.in.xdr.trendmicro.com",
	"au": "https://api.au.xdr.trendmicro.com",
}

func init() {
	Register(&visionOneIntegration{})
}

func (v *visionOneIntegration) ID() string { return "visionone" }

func (v *visionOneIntegration) DisplayName() string { return "Trend Micro Vision One" }

func (v *visionOneIntegration) Validate(cfg config.AdvancedActionsConfig) error {
	vo := cfg.VisionOne
	if vo.APIToken == "" {
		return fmt.Errorf("Vision One API token is required")
	}
	if vo.Region == "" {
		return fmt.Errorf("Vision One region is required")
	}
	if _, ok := visionOneRegions[vo.Region]; !ok {
		regions := make([]string, 0, len(visionOneRegions))
		for k := range visionOneRegions {
			regions = append(regions, k)
		}
		return fmt.Errorf("Vision One region %q is not valid (use: %s)", vo.Region, strings.Join(regions, ", "))
	}
	return nil
}

func (v *visionOneIntegration) BlockIP(req Request) error {
	if err := v.Validate(req.Config); err != nil {
		return err
	}
	if err := ValidateIP(req.IP); err != nil {
		return fmt.Errorf("visionone block: %w", err)
	}
	return v.modifySuspiciousObject(req, true)
}

func (v *visionOneIntegration) UnblockIP(req Request) error {
	if err := v.Validate(req.Config); err != nil {
		return err
	}
	if err := ValidateIP(req.IP); err != nil {
		return fmt.Errorf("visionone unblock: %w", err)
	}
	return v.modifySuspiciousObject(req, false)
}

// =========================================================================
//  Vision One Suspicious Objects API
// =========================================================================

type soObject struct {
	Type             string `json:"type"`
	Value            string `json:"value"`
	RiskLevel        string `json:"riskLevel,omitempty"`
	Description      string `json:"description,omitempty"`
	DaysToExpiration int    `json:"daysToExpiration,omitempty"`
}

type soResponseItem struct {
	Status int    `json:"status"`
	Task   string `json:"task,omitempty"`
}

func (v *visionOneIntegration) modifySuspiciousObject(req Request, add bool) error {
	cfg := req.Config.VisionOne
	baseURL := strings.TrimSuffix(visionOneRegions[cfg.Region], "/")
	endpoint := baseURL + "/v3.0/threatintel/suspiciousObjects"

	client := &http.Client{Timeout: 15 * time.Second}
	if cfg.SkipTLSVerify {
		client.Transport = &http.Transport{
			TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
		}
	}

	riskLevel := cfg.RiskLevel
	if riskLevel == "" {
		riskLevel = "high"
	}
	description := cfg.Description
	if description == "" {
		description = "Blocked by Fail2ban-UI"
	}

	var payload []soObject
	if add {
		obj := soObject{
			Type:        "ip",
			Value:       req.IP,
			RiskLevel:   riskLevel,
			Description: description,
		}
		if cfg.DaysToExpiration > 0 {
			obj.DaysToExpiration = cfg.DaysToExpiration
		}
		payload = []soObject{obj}
	} else {
		payload = []soObject{{Type: "ip", Value: req.IP}}
	}

	body, err := json.Marshal(payload)
	if err != nil {
		return fmt.Errorf("visionone: failed to marshal payload: %w", err)
	}

	method := http.MethodPost
	if !add {
		method = http.MethodDelete
	}

	if req.Logger != nil {
		req.Logger("Vision One API %s %s payload=%s", method, endpoint, string(body))
	}

	httpReq, err := http.NewRequestWithContext(req.Context, method, endpoint, bytes.NewReader(body))
	if err != nil {
		return fmt.Errorf("visionone: failed to create request: %w", err)
	}
	httpReq.Header.Set("Authorization", "Bearer "+cfg.APIToken)
	httpReq.Header.Set("Content-Type", "application/json")
	httpReq.Header.Set("TMV1-Query", "type:ip")

	resp, err := client.Do(httpReq)
	if err != nil {
		return fmt.Errorf("visionone: API request failed: %w", err)
	}
	defer resp.Body.Close()

	respBody, _ := io.ReadAll(resp.Body)

	// Vision One returns 207 Multi-Status for both add and delete.
	// 201 Created is also acceptable for add.
	if resp.StatusCode != http.StatusMultiStatus && resp.StatusCode != http.StatusCreated && resp.StatusCode != http.StatusOK {
		return fmt.Errorf("visionone: unexpected status %s: %s", resp.Status, strings.TrimSpace(string(respBody)))
	}

	// Parse multi-status response and surface any per-item errors.
	var items []soResponseItem
	if err := json.Unmarshal(respBody, &items); err == nil {
		for _, item := range items {
			// 409 Conflict on add means IP already exists — not an error.
			if item.Status >= 400 && !(add && item.Status == 409) {
				return fmt.Errorf("visionone: per-item error status %d for IP %s", item.Status, req.IP)
			}
		}
	}

	action := "added to"
	if !add {
		action = "removed from"
	}
	if req.Logger != nil {
		req.Logger("Vision One: IP %s %s Suspicious Objects list (region: %s)", req.IP, action, cfg.Region)
	}

	return nil
}
