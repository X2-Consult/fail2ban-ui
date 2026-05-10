// "Ignore IPs" tag management for Fail2ban UI
"use strict";

// =========================================================================
//  Tag Rendering, Adding and Removing Functions
// =========================================================================

function renderIgnoreIPsTags(ips) {
  const container = document.getElementById('ignoreIPsTags');
  if (!container) return;
  container.innerHTML = '';
  if (ips && ips.length > 0) {
    ips.forEach(function(ip) {
      if (ip && ip.trim()) {
        addIgnoreIPTag(ip.trim());
      }
    });
  }
}

function addIgnoreIPTag(ip) {
  if (!ip || !ip.trim()) return;
  const trimmedIP = ip.trim();
  if (typeof isValidIP === 'function' && !isValidIP(trimmedIP)) {
    if (typeof showToast === 'function') {
      showToast('Invalid IP address, CIDR, or hostname: ' + trimmedIP, 'error');
    }
    return;
  }
  const container = document.getElementById('ignoreIPsTags');
  if (!container) return;
  const existingTags = Array.from(container.querySelectorAll('.ignore-ip-tag')).map(tag => tag.dataset.ip);
  if (existingTags.includes(trimmedIP)) {
    return;
  }
  const tag = document.createElement('span');
  tag.className = 'ignore-ip-tag inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-blue-100 text-blue-800';
  tag.dataset.ip = trimmedIP;
  const escapedIP = escapeHtml(trimmedIP);
  tag.innerHTML = escapedIP + ' <button type="button" class="ml-1 text-blue-600 hover:text-blue-800 focus:outline-none" onclick="removeIgnoreIPTag(\'' + escapedIP.replace(/'/g, "\\'") + '\')">×</button>';
  container.appendChild(tag);
  const input = document.getElementById('ignoreIPInput');
  if (input) input.value = '';
}

function removeIgnoreIPTag(ip) {
  const container = document.getElementById('ignoreIPsTags');
  if (!container) return;
  const escapedIP = escapeHtml(ip);
  const tag = container.querySelector('.ignore-ip-tag[data-ip="' + escapedIP.replace(/"/g, '&quot;') + '"]');
  if (tag) {
    tag.remove();
  }
}

// =========================================================================
//  Input Handling
// =========================================================================

function setupIgnoreIPsInput() {
  const input = document.getElementById('ignoreIPInput');
  if (!input) return;
  let lastValue = '';
  input.addEventListener('input', function(e) {
    let value = this.value;
    const filtered = value.replace(/[^0-9a-zA-Z:.\/\-\_\s]/g, '');
    if (value !== filtered) {
      this.value = filtered;
    }
    lastValue = filtered;
  });
  input.addEventListener('keydown', function(e) {
    if (e.key === 'Enter' || e.key === ',') {
      e.preventDefault();
      const value = input.value.trim();
      if (value) {
        const ips = value.split(/[,\s]+/).filter(ip => ip.trim());
        ips.forEach(ip => addIgnoreIPTag(ip.trim()));
      }
    }
  });
  input.addEventListener('blur', function(e) {
    const value = input.value.trim();
    if (value) {
      const ips = value.split(/[,\s]+/).filter(ip => ip.trim());
      ips.forEach(ip => addIgnoreIPTag(ip.trim()));
    }
  });
  input.addEventListener('paste', function(e) {
    setTimeout(() => {
      const value = input.value.trim();
      if (value) {
        if (value.includes(' ') || value.includes(',')) {
          const ips = value.split(/[,\s]+/).filter(ip => ip.trim());
          ips.forEach(ip => addIgnoreIPTag(ip.trim()));
          input.value = '';
        }
      }
    }, 0);
  });
}

// =========================================================================
//  Data Access
// =========================================================================

function getIgnoreIPsArray() {
  const container = document.getElementById('ignoreIPsTags');
  if (!container) return [];
  const tags = container.querySelectorAll('.ignore-ip-tag');
  return Array.from(tags).map(tag => tag.dataset.ip).filter(ip => ip && ip.trim());
}

// =========================================================================
//  Dedicated Ignore List Section
// =========================================================================

function loadIgnoreListSection() {
  fetch(appPath('/api/ignorelist'), { headers: serverHeaders() })
    .then(function(res) { return res.json(); })
    .then(function(data) {
      renderIgnoreListTable(data.ignoreips || []);
    })
    .catch(function(err) {
      showToast('Error loading ignore list: ' + err, 'error');
    });
}

function renderIgnoreListTable(ips) {
  var tbody = document.getElementById('ignoreListTableBody');
  if (!tbody) return;
  if (!ips || ips.length === 0) {
    tbody.innerHTML = '<tr><td colspan="2" class="px-4 py-8 text-center text-gray-500 text-sm">No entries in the ignore list. Add an IP or CIDR below.</td></tr>';
    return;
  }
  tbody.innerHTML = ips.map(function(ip) {
    var safe = escapeHtml(ip);
    return '<tr class="border-t border-gray-100 hover:bg-gray-50">'
      + '<td class="px-4 py-3 font-mono text-sm text-gray-900">' + safe + '</td>'
      + '<td class="px-4 py-3 text-right">'
      + '<button class="text-red-600 hover:text-red-800 text-sm font-medium" onclick="removeIgnoreListEntry(\'' + safe.replace(/'/g, "\\'") + '\')">'
      + 'Remove'
      + '</button>'
      + '</td>'
      + '</tr>';
  }).join('');
}

function addIgnoreListEntry() {
  var input = document.getElementById('ignoreListInput');
  if (!input) return;
  var ip = input.value.trim();
  if (!ip) return;
  if (typeof isValidIP === 'function' && !isValidIP(ip)) {
    showToast('Invalid IP address, CIDR, or hostname: ' + ip, 'error');
    return;
  }
  fetch(appPath('/api/ignorelist'), {
    method: 'POST',
    headers: Object.assign({'Content-Type': 'application/json'}, serverHeaders()),
    body: JSON.stringify({ ip: ip })
  })
    .then(function(res) { return res.json(); })
    .then(function(data) {
      if (data.error) {
        showToast('Error: ' + data.error, 'error');
      } else {
        input.value = '';
        renderIgnoreListTable(data.ignoreips || []);
        showToast(ip + ' added to ignore list', 'success');
      }
    })
    .catch(function(err) {
      showToast('Error: ' + err, 'error');
    });
}

function removeIgnoreListEntry(ip) {
  if (!confirm('Remove ' + ip + ' from the ignore list?')) return;
  fetch(appPath('/api/ignorelist?ip=' + encodeURIComponent(ip)), {
    method: 'DELETE',
    headers: serverHeaders()
  })
    .then(function(res) { return res.json(); })
    .then(function(data) {
      if (data.error) {
        showToast('Error: ' + data.error, 'error');
      } else {
        renderIgnoreListTable(data.ignoreips || []);
        showToast(ip + ' removed from ignore list', 'success');
      }
    })
    .catch(function(err) {
      showToast('Error: ' + err, 'error');
    });
}

function setupIgnoreListSectionInput() {
  var input = document.getElementById('ignoreListInput');
  if (!input) return;
  input.addEventListener('keydown', function(e) {
    if (e.key === 'Enter') {
      e.preventDefault();
      addIgnoreListEntry();
    }
  });
}
