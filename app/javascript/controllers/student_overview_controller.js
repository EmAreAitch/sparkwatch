import { Controller } from "@hotwired/stimulus"
import { Chart, registerables } from "chart.js"
import { Grid, html } from "gridjs"
import dashboardOverview from "api/Dashboard/OverviewApi"
import dashboardStudent from "api/Dashboard/StudentsApi"

Chart.register(...registerables)

export default class extends Controller {
  static targets = [
    "canvas", "chartSkeleton", "tabButton", "tabPanel", "gridContainer",
    "totalStudents", "activeThisWeek", "atRisk", "highPerformers",
    "atRiskCount", "highPerformersCount", "inactiveCount"
  ]

  charts = []
  fetchCache = new Map()

  connect() {
    this.loadAll()
    this.showTab("at-risk")
  }

  disconnect() {
    this.charts.forEach(c => c?.destroy())
    this.fetchCache.clear()
  }

  async loadAll() {
    const widgets = ['kpis', ...this.canvasTargets
      .map(c => c.dataset.chartWidget)
      .filter(Boolean)]

    try {
      const url = dashboardOverview.student.path({ query: { widgets } })
      const res = await fetch(url)
      const data = await res.json()

      if (data.kpis) this.setKPIs(data.kpis)
      this.canvasTargets.forEach(canvas => {
        const chartData = data[canvas.dataset.chartWidget]
        if (chartData) {
          this.makeChart(canvas, chartData)
          canvas.previousElementSibling?.classList.add('hidden')
          canvas.classList.remove('hidden')
        }
      })
    } catch (e) {
      console.error(e)
    }
  }

  setKPIs(k) {
    this.totalStudentsTarget.textContent = k.total_students?.toLocaleString() || '0'
    this.activeThisWeekTarget.textContent = k.active_this_week?.toLocaleString() || '0'
    this.atRiskTarget.textContent = k.at_risk?.toLocaleString() || '0'
    this.highPerformersTarget.textContent = k.high_performers?.toLocaleString() || '0'
    this.atRiskCountTarget.textContent = k.at_risk?.toLocaleString() || '0'
    this.highPerformersCountTarget.textContent = k.high_performers?.toLocaleString() || '0'
    if (k.inactive_students) this.inactiveCountTarget.textContent = k.inactive_students.toLocaleString()
  }

  makeChart(canvas, data) {
    const type = canvas.dataset.chartType

    if (type === "scatter") {
      const quads = { crisis: [], struggling: [], coasting: [], thriving: [] }
      data.forEach(d => quads[d.quadrant].push({ x: d.engagement, y: d.risk, r: Math.sqrt(d.count) * 3, count: d.count }))

      this.charts.push(new Chart(canvas, {
        type: 'bubble',
        data: {
          datasets: [
            { label: 'Crisis', data: quads.crisis, backgroundColor: '#ef444499', borderColor: '#ef4444', borderWidth: 2 },
            { label: 'Struggling', data: quads.struggling, backgroundColor: '#f9731699', borderColor: '#f97316', borderWidth: 2 },
            { label: 'Coasting', data: quads.coasting, backgroundColor: '#fbbf2499', borderColor: '#fbbf24', borderWidth: 2 },
            { label: 'Thriving', data: quads.thriving, backgroundColor: '#22c55e99', borderColor: '#22c55e', borderWidth: 2 }
          ]
        },
        options: {
          responsive: true, maintainAspectRatio: false,
          plugins: {
            legend: { display: true, position: 'bottom' },
            tooltip: { callbacks: { label: c => `${c.raw.count} students: Risk ${c.raw.y}%, Engagement ${c.raw.x}%` } }
          },
          scales: {
            x: { title: { display: true, text: 'Engagement %' }, min: 0, max: 100 },
            y: { title: { display: true, text: 'Risk Score %' }, min: 0, max: 100 }
          }
        }
      }))
    } else {
      const colors = {
        engagement_distribution: ["rgb(239,68,68)", "rgb(251,146,60)", "rgb(251,191,36)", "rgb(34,197,94)", "rgb(16,185,129)"],
        cohort_distribution: ["rgb(59,130,246)", "rgb(16,185,129)", "rgb(139,92,246)", "rgb(245,158,11)", "rgb(236,72,153)"],
        momentum_distribution: ["rgb(239,68,68)", "rgb(251,146,60)", "rgb(148,163,184)", "rgb(34,197,94)", "rgb(16,185,129)"]
      }[canvas.dataset.chartWidget] || ['#6366f1', '#8b5cf6', '#ec4899']

      const opts = { responsive: true, maintainAspectRatio: false, plugins: { legend: { display: type === "doughnut", position: "bottom" } } }
      if (type !== "doughnut") {
        opts.scales = canvas.dataset.chartOrientation === "horizontal" ? { indexAxis: 'y', x: { beginAtZero: true } } : { y: { beginAtZero: true } }
      }

      this.charts.push(new Chart(canvas, {
        type,
        data: { labels: Object.keys(data), datasets: [{ data: Object.values(data), backgroundColor: colors, label: 'Students' }] },
        options: opts
      }))
    }
  }

  switchTab(e) {
    const tab = e.currentTarget.dataset.tab
    this.tabButtonTargets.forEach(b => {
      const active = b === e.currentTarget
      b.classList.toggle("border-indigo-500", active)
      b.classList.toggle("text-indigo-600", active)
      b.classList.toggle("border-transparent", !active)
      b.classList.toggle("text-gray-500", !active)
    })
    this.showTab(tab)
  }

  showTab(tab) {
    this.tabPanelTargets.forEach(p => p.classList.toggle("hidden", p.dataset.tab !== tab))

    const container = this.gridContainerTargets.find(c => c.dataset.gridType === tab)
    if (!container || container.children.length) return

    const widgetMap = { 'at-risk': 'at_risk_students', 'high-performers': 'high_performers', 'inactive': 'inactive_students' }
    const widget = widgetMap[tab]
    if (!widget) return

    new Grid({
      columns: this.cols(tab),
      data: () => this.fetchTable(widget),
      search: true,
      pagination: { limit: 10 },
      resizable: true,
      className: { td: "text-sm text-center", th: "text-sm" }
    }).render(container)
  }

  async fetchTable(widget) {
    if (this.fetchCache.has(widget)) return this.fetchCache.get(widget)

    if (this.fetchCache.has(widget)) return this.fetchCache.get(widget)

    const url = dashboardOverview.student.path({ query: { widgets: [widget] } })

    const promise = fetch(url)
      .then(r => r.json())
      .then(d => { this.fetchCache.delete(widget); return d[widget] || [] })
      .catch(() => { this.fetchCache.delete(widget); return [] })

    this.fetchCache.set(widget, promise)
    return promise
  }

  cols(tab) {
    const base = [
      { name: 'Name', id: 'name' },
      { name: 'Email', id: 'email' },
      { name: 'Cohort', id: tab === 'inactive' ? 'cohort_name' : 'cohort' }
    ]

    const specific = {
      'at-risk': [
        {
          name: 'Risk Score', id: 'risk_score_percent', sort: true,
          formatter: c => html(`<span class="px-2 py-1 text-xs rounded-full bg-red-100 text-red-800 font-medium">${c}%</span>`)
        },
        { name: 'Engagement', id: 'engagement_score', sort: true, formatter: c => `${c}%` }
      ],
      'high-performers': [
        {
          name: 'Engagement', id: 'engagement_score', sort: true,
          formatter: c => html(`<span class="px-2 py-1 text-xs rounded-full bg-green-100 text-green-800 font-medium">${c}%</span>`)
        },
        { name: 'Risk Score', id: 'risk_score_percent', sort: true, formatter: c => `${c}%` }
      ],
      'inactive': [
        { name: 'Last Active', id: 'last_activity_at', sort: true, formatter: c => this.timeAgo(c) },
        { name: 'Engagement', id: 'engagement_score', sort: true, formatter: c => `${c}%` },
        { name: 'Risk Score', id: 'risk_score_percent', sort: true, formatter: c => `${c}%` }
      ]
    }[tab] || []

    const lastActive = tab !== 'inactive' ? [{ name: 'Last Active', id: 'last_activity_at', sort: true, formatter: c => this.timeAgo(c) }] : []
    const action = { name: 'Action', id: 'id', formatter: (c) => html(`<a href="${dashboardStudent.show.path({ id: c })}" class="text-indigo-600 hover:text-indigo-900 text-sm font-medium">View</a>`) }

    return [...base, ...specific, ...lastActive, action]
  }

  timeAgo(t) {
    if (!t) return 'Never'
    const d = Math.floor((new Date() - new Date(t)) / 86400000)
    if (d === 0) return 'Today'
    if (d === 1) return '1 day ago'
    if (d < 7) return `${d} days ago`
    if (d < 30) return `${Math.floor(d / 7)} weeks ago`
    return `${Math.floor(d / 30)} months ago`
  }
}

