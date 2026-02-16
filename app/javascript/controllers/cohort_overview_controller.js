import { Controller } from "@hotwired/stimulus"
import { Chart, registerables } from "chart.js"
import { Grid, html } from "gridjs"
import dashboardOverview from "api/Dashboard/OverviewApi"

Chart.register(...registerables)

export default class extends Controller {
  static targets = [
    "canvas", "chartSkeleton", "tabButton", "tabPanel", "gridContainer",
    "totalCohorts", "avgCohortSize", "avgEngagement", "uniquePrograms"
  ]

  charts = []
  fetchCache = new Map()

  connect() {
    this.initializeDashboard()
  }

  disconnect() {
    this.cleanup()
  }

  async initializeDashboard() {
    this.loadDashboardData()
    this.showTab("high-performing")
  }

  cleanup() {
    this.charts.forEach(chart => chart?.destroy())
    this.fetchCache.clear()
  }

  async loadDashboardData() {
    const widgets = this.getRequiredWidgets()

    try {
      const url = dashboardOverview.cohort.path({ query: { widgets } })
      const res = await fetch(url)
      const data = await res.json()

      if (data.kpis) this.updateKPIs(data.kpis)
      this.renderCharts(data)
    } catch (error) {
      console.error(error)
    }
  }

  switchTab(event) {
    const tab = event.currentTarget.dataset.tab
    this.updateTabButtons(event.currentTarget)
    this.showTab(tab)
  }

  showTab(tab) {
    this.showTabPanel(tab)
    this.loadTabGrid(tab)
  }

  createChart(canvas, data) {
    const chartType = canvas.dataset.chartType
    const widget = canvas.dataset.chartWidget

    const builders = {
      scatter: () => this.buildScatterChart(canvas, data),
      doughnut: () => this.buildDoughnutChart(canvas, data),
      bar: () => this.buildBarChart(canvas, data, widget)
    }

    const builder = builders[chartType]
    if (builder) builder()
  }

  renderCharts(data) {
    this.canvasTargets.forEach(canvas => {
      const chartData = data[canvas.dataset.chartWidget]
      if (!chartData) return

      this.createChart(canvas, chartData)
      this.showCanvas(canvas)
    })
  }

  loadTabGrid(tab) {
    const container = this.getGridContainer(tab)
    if (!container || container.children.length) return

    const widget = this.getWidgetForTab(tab)
    if (!widget) return

    new Grid({
      columns: this.getGridColumns(tab),
      data: () => this.fetchTableData(widget),
      search: true,
      pagination: { limit: 10 },
      resizable: true,
      className: {
        td: "text-sm text-center",
        th: "text-sm"
      }
    }).render(container)
  }

  updateKPIs(kpis) {
    this.totalCohortsTarget.textContent = kpis.total_cohorts?.toLocaleString() || '0'
    this.avgCohortSizeTarget.textContent = kpis.avg_cohort_size?.toLocaleString() || '0'
    this.avgEngagementTarget.textContent = kpis.avg_engagement_percent ? `${kpis.avg_engagement_percent}%` : '0%'
    this.uniqueProgramsTarget.textContent = kpis.unique_programs?.toLocaleString() || '0'
  }

  buildScatterChart(canvas, data) {
    const scatterData = data.map(d => ({ x: d.size, y: d.engagement_percent }))

    this.charts.push(new Chart(canvas, {
      type: 'scatter',
      data: {
        datasets: [{
          label: 'Cohorts',
          data: scatterData,
          backgroundColor: 'rgba(79, 70, 229, 0.6)',
          borderColor: 'rgb(79, 70, 229)',
          pointRadius: 5
        }]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
          legend: { display: false },
          tooltip: {
            callbacks: {
              label: c => `Size: ${c.raw.x}, Engagement: ${c.raw.y}%`
            }
          }
        },
        scales: {
          x: {
            title: { display: true, text: 'Cohort Size (Students)' },
            min: 10,
            max: 40
          },
          y: {
            title: { display: true, text: 'Engagement %' },
            min: 50,
            max: 100
          }
        }
      }
    }))
  }

  buildDoughnutChart(canvas, data) {
    const colors = [
      'rgb(59, 130, 246)',
      'rgb(16, 185, 129)',
      'rgb(139, 92, 246)',
      'rgb(245, 158, 11)',
      'rgb(236, 72, 153)'
    ]

    this.charts.push(new Chart(canvas, {
      type: 'doughnut',
      data: {
        labels: Object.keys(data),
        datasets: [{
          data: Object.values(data),
          backgroundColor: colors
        }]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
          legend: { position: 'bottom' }
        }
      }
    }))
  }

  buildBarChart(canvas, data, widget) {
    const isHorizontal = canvas.dataset.chartOrientation === "horizontal"
    if (!isHorizontal) return

    const config = this.getBarChartConfig(data, widget)

    this.charts.push(new Chart(canvas, {
      type: 'bar',
      data: {
        labels: config.labels,
        datasets: [{
          data: config.values,
          backgroundColor: config.colors,
          label: config.label
        }]
      },
      options: {
        indexAxis: 'y',
        responsive: true,
        maintainAspectRatio: false,
        plugins: { legend: { display: false } },
        scales: {
          x: {
            beginAtZero: true,
            max: 100,
            title: { display: true, text: config.label }
          }
        }
      }
    }))
  }

  updateTabButtons(activeButton) {
    this.tabButtonTargets.forEach(button => {
      const isActive = button === activeButton
      button.classList.toggle("border-indigo-500", isActive)
      button.classList.toggle("text-indigo-600", isActive)
      button.classList.toggle("border-transparent", !isActive)
      button.classList.toggle("text-gray-500", !isActive)
    })
  }

  showTabPanel(tab) {
    this.tabPanelTargets.forEach(panel => {
      panel.classList.toggle("hidden", panel.dataset.tab !== tab)
    })
  }

  showCanvas(canvas) {
    canvas.previousElementSibling?.classList.add('hidden')
    canvas.classList.remove('hidden')
  }

  async fetchTableData(widget) {
    if (this.fetchCache.has(widget)) return this.fetchCache.get(widget)

    const url = dashboardOverview.cohort.path({
      query: { widgets: [widget] }
    })

    const promise = fetch(url)
      .then(r => r.json())
      .then(d => {
        this.fetchCache.delete(widget)
        return d[widget] || []
      })
      .catch(() => {
        this.fetchCache.delete(widget)
        return []
      })

    this.fetchCache.set(widget, promise)
    return promise
  }

  getRequiredWidgets() {
    const chartWidgets = this.canvasTargets
      .map(canvas => canvas.dataset.chartWidget)
      .filter(Boolean)

    return ['kpis', ...chartWidgets]
  }

  async fetchWidgetData(widgets) {
    try {
      const response = await fetch(dashboardOverview.cohort.path({ query: { widgets } }))
      return await response.json()
    } catch (error) {
      console.error(error)
      return {}
    }
  }

  getBarChartConfig(data, widget) {
    const configs = {
      instructor_performance: {
        labels: data.map(d => d.instructor_name),
        values: data.map(d => d.avg_engagement_percent),
        colors: data.map(d => this.getEngagementColor(d.avg_engagement_percent)),
        label: 'Avg Engagement %'
      },
      completion_projections: {
        labels: data.map(d => d.program),
        values: data.map(d => d.projected_completion_percent),
        colors: data.map(d => this.getCompletionColor(d.projected_completion_percent)),
        label: 'Projected Completion %'
      }
    }

    return configs[widget] || {}
  }

  getGridContainer(tab) {
    return this.gridContainerTargets.find(c => c.dataset.gridType === tab)
  }

  getWidgetForTab(tab) {
    const widgetMap = {
      'high-performing': 'high_performing_cohorts',
      'needs-attention': 'needs_attention_cohorts',
      'most-active': 'most_active_cohorts'
    }
    return widgetMap[tab]
  }

  getGridColumns(tab) {
    const base = [
      { name: 'Cohort', id: 'cohort_name' },
      { name: 'Program', id: 'program' },
      { name: 'Instructor', id: 'instructor_name' },
      { name: 'Students', id: 'student_count', sort: true }
    ]

    const specific = {
      'high-performing': [{
        name: 'Avg Engagement',
        id: 'avg_engagement_percent',
        sort: true,
        formatter: c => html(`<span class="px-2 py-1 text-xs rounded-full bg-green-100 text-green-800 font-medium">${c}%</span>`)
      }],
      'needs-attention': [
        {
          name: 'Engagement',
          id: 'engagement_percent',
          sort: true,
          formatter: c => html(`<span class="px-2 py-1 text-xs rounded-full ${this.getEngagementBadgeClass(c)}">${c}%</span>`)
        },
        {
          name: 'Avg Risk',
          id: 'risk_percent',
          sort: true,
          formatter: c => html(`<span class="px-2 py-1 text-xs rounded-full bg-red-100 text-red-800 font-medium">${c}%</span>`)
        }
      ],
      'most-active': [{
        name: 'Total Activities',
        id: 'activity_count',
        sort: true,
        formatter: c => c.toLocaleString()
      }]
    }

    const action = {
      name: 'Action',
      id: 'id',
      formatter: (cell) => html(`<a href="/dashboard/cohorts/${cell}" class="text-indigo-600 hover:text-indigo-900 text-sm font-medium">View</a>`)
    }

    return [...base, ...(specific[tab] || []), action]
  }

  getEngagementColor(value) {
    if (value >= 85) return 'rgb(34, 197, 94)'
    if (value >= 70) return 'rgb(59, 130, 246)'
    return 'rgb(239, 68, 68)'
  }

  getCompletionColor(value) {
    if (value >= 70) return 'rgb(34, 197, 94)'
    if (value >= 60) return 'rgb(59, 130, 246)'
    return 'rgb(245, 158, 11)'
  }

  getEngagementBadgeClass(value) {
    if (value >= 85) return 'bg-green-100 text-green-800 font-medium'
    if (value >= 70) return 'bg-blue-100 text-blue-800 font-medium'
    return 'bg-red-100 text-red-800 font-medium'
  }
}
