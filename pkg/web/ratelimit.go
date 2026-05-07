package web

import (
	"net/http"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
)

// =========================================================================
//  Token-bucket rate limiter (per source IP, stdlib only)
// =========================================================================

type tokenBucket struct {
	tokens   float64
	capacity float64
	refillPS float64 // tokens added per second
	lastSeen time.Time
}

type ipRateLimiter struct {
	mu      sync.Mutex
	buckets map[string]*tokenBucket
	// How long an idle entry lives before being pruned.
	idleTTL time.Duration
}

func newIPRateLimiter(capacity, refillPerSecond float64) *ipRateLimiter {
	rl := &ipRateLimiter{
		buckets: make(map[string]*tokenBucket),
		idleTTL: 10 * time.Minute,
	}
	go rl.pruneLoop()
	return rl
}

func (rl *ipRateLimiter) allow(ip string, capacity, refillPS float64) bool {
	rl.mu.Lock()
	defer rl.mu.Unlock()

	now := time.Now()
	b, ok := rl.buckets[ip]
	if !ok {
		b = &tokenBucket{tokens: capacity, capacity: capacity, refillPS: refillPS}
		rl.buckets[ip] = b
	}

	elapsed := now.Sub(b.lastSeen).Seconds()
	b.lastSeen = now
	b.tokens = min64(b.capacity, b.tokens+elapsed*b.refillPS)

	if b.tokens < 1 {
		return false
	}
	b.tokens--
	return true
}

func (rl *ipRateLimiter) pruneLoop() {
	t := time.NewTicker(5 * time.Minute)
	defer t.Stop()
	for range t.C {
		rl.mu.Lock()
		cutoff := time.Now().Add(-rl.idleTTL)
		for ip, b := range rl.buckets {
			if b.lastSeen.Before(cutoff) {
				delete(rl.buckets, ip)
			}
		}
		rl.mu.Unlock()
	}
}

func min64(a, b float64) float64 {
	if a < b {
		return a
	}
	return b
}

// Global limiters — initialised once.
var (
	// callbackLimiter: 60 requests/minute per IP on the public ban/unban endpoints.
	callbackLimiter = newIPRateLimiter(60, 1)
	// authLimiter: 10 requests/minute per IP on OIDC endpoints.
	authLimiter = newIPRateLimiter(10, 10.0/60)
)

// RateLimitCallback limits the public /api/ban and /api/unban endpoints.
func RateLimitCallback() gin.HandlerFunc {
	return func(c *gin.Context) {
		ip := c.ClientIP()
		if !callbackLimiter.allow(ip, 60, 1) {
			c.AbortWithStatusJSON(http.StatusTooManyRequests, gin.H{
				"error": "rate limit exceeded — try again later",
			})
			return
		}
		c.Next()
	}
}

// RateLimitAuth limits the /auth/login and /auth/callback endpoints.
func RateLimitAuth() gin.HandlerFunc {
	return func(c *gin.Context) {
		ip := c.ClientIP()
		if !authLimiter.allow(ip, 10, 10.0/60) {
			c.AbortWithStatusJSON(http.StatusTooManyRequests, gin.H{
				"error": "too many authentication attempts — try again later",
			})
			return
		}
		c.Next()
	}
}
