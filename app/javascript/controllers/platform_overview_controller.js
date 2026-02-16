import { Controller } from "@hotwired/stimulus"
import { Chart, registerables } from "chart.js"
import { Grid, html } from "gridjs"
import dashboardOverview from "api/Dashboard/OverviewApi"

Chart.register(...registerables)

export default class extends Controller {
  static targets = [
    "canvas", "chartSkeleton",
    "totalStudents", "activeCohorts", "avgEngagement", "atRiskStudents",
    "gridContainer"
  ]

  charts = []
  fetchCache = new Map()

  connect() {
    this.loadAll()
  }

  disconnect() {
    this.charts.forEach(c => c?.destroy())
    this.fetchCache.clear()
  }

  async loadAll() {
    const widgets = [
      'kpis',
      'weekly_engagement_trend',
      'risk_distribution',
      'weekly_activity_breakdown',
      'program_performance',
      'at_risk_students'
    ]

    try {
      const url = dashboardOverview.platform.path({ query: { widgets } })
      const res = await fetch(url)
      const data = await res.json()

      if (data.kpis) this.setKPIs(data.kpis)

      // Render charts
      this.canvasTargets.forEach(canvas => {
        const chartData = data[canvas.dataset.chartWidget]
        if (chartData) {
          this.makeChart(canvas, chartData)
          canvas.previousElementSibling?.classList.add('hidden')
          canvas.classList.remove('hidden')
        }
      })

      // Render at-risk students table
      if (data.at_risk_students) {
        this.renderAtRiskTable(data.at_risk_students)
      }
    } catch (e) {
      console.error('Failed to load platform overview data:', e)
    }
  }

  setKPIs(k) {
    this.totalStudentsTarget.textContent = k.total_students?.toLocaleString() || '0'
    this.activeCohortsTarget.textContent = k.active_cohorts?.toLocaleString() || '0'

    if (k.avg_engagement_percent !== undefined) {
      this.avgEngagementTarget.textContent = `${k.avg_engagement_percent}%`
    }

    this.atRiskStudentsTarget.textContent = k.at_risk_students?.toLocaleString() || '0'
  }

  makeChart(canvas, data) {
    const widget = canvas.dataset.chartWidget
    const type = canvas.dataset.chartType

    let chartConfig = null

    switch (widget) {
      case 'weekly_engagement_trend':
        chartConfig = this.lineChartConfig(data)
        break
      case 'risk_distribution':
        chartConfig = this.doughnutChartConfig(data)
        break
      case 'weekly_activity_breakdown':
        chartConfig = this.barChartConfig(data, ['#4f46e5', '#8b5cf6', '#ec4899', '#f59e0b', '#10b981'])
        break
      case 'program_performance':
        chartConfig = this.barChartConfig(data, [
          'rgb(59, 130, 246)',
          'rgb(16, 185, 129)',
          'rgb(139, 92, 246)',
          'rgb(245, 158, 11)',
          'rgb(236, 72, 153)'
        ])
        break
      default:
        console.warn(`Unknown chart widget: ${widget}`)
        return
    }

    if (chartConfig) {
      this.charts.push(new Chart(canvas, chartConfig))
    }
  }

  lineChartConfig(data) {
    // data is expected to be an object with date keys
    const labels = Object.keys(data).map(dateStr => {
      const date = new Date(dateStr)
      return date.toLocaleDateString('en-US', { month: 'short', day: 'numeric' })
    })
    const values = Object.values(data)

    return {
      type: 'line',
      data: {
        labels,
        datasets: [{
          data: values,
          borderColor: '#4f46e5',
          backgroundColor: 'rgba(79,70,229,0.1)',
          tension: 0.4,
          fill: true,
          label: 'Engagement %'
        }]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
          legend: { display: false }
        },
        scales: {
          y: { beginAtZero: true }
        }
      }
    }
  }

  doughnutChartConfig(data) {
    const labels = Object.keys(data)
    const values = Object.values(data)
    const colors = ['#f97316', '#ef4444', '#22c55e']

    return {
      type: 'doughnut',
      data: {
        labels,
        datasets: [{
          data: values,
          backgroundColor: colors
        }]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
          legend: { display: true, position: 'bottom' }
        }
      }
    }
  }

  barChartConfig(data, colors) {
    // data could be an object with string keys (like activity types)
    const labels = Object.keys(data).map(key => {
      // Humanize snake_case keys
      return key.split('_').map(word =>
        word.charAt(0).toUpperCase() + word.slice(1)
      ).join(' ')
    })
    const values = Object.values(data)

    return {
      type: 'bar',
      data: {
        labels,
        datasets: [{
          data: values,
          backgroundColor: colors.slice(0, values.length),
          label: 'Count'
        }]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
          legend: { display: false }
        },
        scales: {
          y: { beginAtZero: true }
        }
      }
    }
  }

  renderAtRiskTable(students) {
    const container = this.gridContainerTarget
    if (!container || container.children.length) return

    new Grid({
      columns: [
        {
          name: 'Student',
          id: 'name',
          formatter: (cell, row) => html(`
            <div>
              <div class="font-medium text-gray-900">${row.cells[0].data}</div>
              <div class="text-sm text-gray-500">${row.cells[1].data}</div>
            </div>
          `)
        },
        { name: 'Email', id: 'email', hidden: true },
        { name: 'Cohort', id: 'cohort' },
        {
          name: 'Risk Score',
          id: 'risk_score_percent',
          sort: true,
          formatter: (c) => html(`
            <span class="px-2 py-1 text-xs rounded-full bg-red-100 text-red-800">
              High (${c}%)
            </span>
          `)
        },
        {
          name: 'Engagement',
          id: 'engagement_score',
          sort: true,
          formatter: (c) => `${c}%`
        },
        {
          name: 'Last Activity',
          id: 'last_activity_at',
          sort: true,
          formatter: (c) => this.formatDate(c)
        },
        {
          name: 'Action',
          id: 'id',
          formatter: (cell) => html(`
            <a href="/dashboard/students/${cell}" class="text-indigo-600 hover:text-indigo-900 text-sm font-medium">
              View
            </a>
          `)
        }
      ],
      data: students,
      resizable: true,
      className: {
        td: "px-6 py-4 whitespace-nowrap text-sm",
        th: "px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase"
      }
    }).render(container)
  }

  formatDate(dateStr) {
    if (!dateStr) return '—'
    const date = new Date(dateStr)
    return date.toLocaleDateString('en-US', {
      month: 'short',
      day: 'numeric',
      year: 'numeric'
    })
  }
}
