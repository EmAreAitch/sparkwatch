import { Controller } from "@hotwired/stimulus"
import { Chart, registerables } from "chart.js"
import { Grid, h } from "gridjs"
import dashboardCohorts from "api/Dashboard/CohortsApi"

Chart.register(...registerables)

export default class extends Controller {
  static values = { cohortId: String }
  static targets = [
    "kpiStudentCount", "kpiAvgEngagement", "kpiTopPerformers", "kpiRiskCount",
    "trendChart", "activityChart", "riskChart", "distributionChart",
    "gridContainer"
  ]

  connect() {
    this.loadData()
  }

  async loadData() {
    // Widgets: H (in info), K (kpis), C1 (trend), C2 (activity), C3 (risk_trend), Dist, Roster
    const widgets = [
      "cohort_info", "kpis",
      "engagement_trend", "activity_breakdown", "risk_trend", "score_distribution",
      "student_roster"
    ]
    const url = dashboardCohorts.show.path({
      id: this.cohortIdValue,
      query: { widgets }
    })

    try {
      const response = await fetch(url, { headers: { "Accept": "application/json" } })
      const data = await response.json()

      this.renderInfo(data.cohort_info)
      this.renderKPIs(data.kpis)
      this.renderCharts(data)
      this.renderGrid(data.student_roster)

    } catch (error) {
      console.error("Failed to load cohort details:", error)
    }
  }

  renderInfo(info) {
    const titleEl = document.getElementById("cohort-title")
    const subtitleEl = document.getElementById("cohort-subtitle")
    if (titleEl) titleEl.textContent = info.name
    if (subtitleEl) subtitleEl.textContent = "Detailed Analytics"

    // Hero Stats
    const instructorEl = document.getElementById("hero-instructor")
    if (instructorEl) instructorEl.textContent = info.instructor

    const programEl = document.getElementById("hero-program")
    if (programEl) programEl.textContent = info.program

    const topStudentEl = document.getElementById("hero-top-student")
    if (topStudentEl) topStudentEl.textContent = info.top_student

    const volEl = document.getElementById("hero-activity-vol")
    if (volEl) volEl.textContent = info.activity_volume
  }

  renderKPIs(kpis) {
    if (this.hasKpiStudentCountTarget) this.kpiStudentCountTarget.textContent = kpis.student_count
    if (this.hasKpiAvgEngagementTarget) this.kpiAvgEngagementTarget.textContent = `${kpis.avg_engagement}%`
    if (this.hasKpiTopPerformersTarget) this.kpiTopPerformersTarget.textContent = kpis.top_performers
    if (this.hasKpiRiskCountTarget) this.kpiRiskCountTarget.textContent = kpis.risk_count
  }

  renderCharts(data) {
    if (data.engagement_trend) this.renderTrendChart(data.engagement_trend)
    if (data.activity_breakdown) this.renderActivityChart(data.activity_breakdown)
    if (data.risk_trend) this.renderRiskTrendChart(data.risk_trend)
    if (data.score_distribution) this.renderDistributionChart(data.score_distribution)
  }

  renderTrendChart(trendData) {
    if (!this.hasTrendChartTarget || !trendData) return
    new Chart(this.trendChartTarget, {
      type: 'line',
      data: {
        labels: trendData.map(d => d.week_label),
        datasets: [
          {
            label: 'This Cohort',
            data: trendData.map(d => d.cohort_avg),
            borderColor: 'rgb(37, 99, 235)', // Blue 600
            tension: 0.3
          },
          {
            label: 'Program Avg',
            data: trendData.map(d => d.program_avg),
            borderColor: 'rgb(156, 163, 175)', // Gray 400
            borderDash: [5, 5],
            tension: 0.3
          }
        ]
      },
      options: { responsive: true, maintainAspectRatio: false }
    })
  }

  renderActivityChart(data) {
    if (!this.hasActivityChartTarget) return
    new Chart(this.activityChartTarget, {
      type: 'bar',
      data: {
        labels: data.map(d => d.date),
        datasets: [{
          label: 'Activity Count',
          data: data.map(d => d.count),
          backgroundColor: 'rgb(52, 211, 153)' // Green
        }]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false
      }
    })
  }

  renderRiskTrendChart(data) {
    if (!this.hasRiskChartTarget || !data) return
    new Chart(this.riskChartTarget, {
      type: 'line',
      data: {
        labels: data.map(d => d.week),
        datasets: [
          {
            label: 'High Risk',
            data: data.map(d => d.high),
            backgroundColor: 'rgba(239, 68, 68, 0.5)',
            borderColor: 'rgb(239, 68, 68)',
            fill: true
          },
          {
            label: 'Medium Risk',
            data: data.map(d => d.medium),
            backgroundColor: 'rgba(250, 204, 21, 0.5)',
            borderColor: 'rgb(250, 204, 21)',
            fill: true
          },
          {
            label: 'Low Risk',
            data: data.map(d => d.low),
            backgroundColor: 'rgba(34, 197, 94, 0.5)',
            borderColor: 'rgb(34, 197, 94)',
            fill: true
          }
        ]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        scales: { y: { stacked: true } },
        elements: { point: { radius: 0 } }
      }
    })
  }

  renderDistributionChart(data) {
    if (!this.hasDistributionChartTarget || !data) return
    new Chart(this.distributionChartTarget, {
      type: 'bar',
      data: {
        labels: Object.keys(data),
        datasets: [{
          label: 'Student Count',
          data: Object.values(data),
          backgroundColor: 'rgb(79, 70, 229)' // Indigo
        }]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        scales: {
          y: { beginAtZero: true, ticks: { stepSize: 1 } }
        }
      }
    })
  }

  renderGrid(students) {
    if (!this.hasGridContainerTarget) return

    this.gridContainerTarget.innerHTML = "" // Clear loading state

    new Grid({
      columns: [
        { name: 'Rank', sort: true },
        { name: 'Name', sort: false },
        { name: 'Email', sort: false },
        {
          name: 'Risk Level',
          sort: true,
          formatter: (cell) => {
            const risk = parseInt(cell)
            let level = "Low", color = "bg-green-100 text-green-800"
            if (risk >= 90) { level = "High"; color = "bg-red-100 text-red-800 font-bold" }
            else if (risk >= 70) { level = "Med"; color = "bg-yellow-100 text-yellow-800" }
            return h('span', { className: `inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium ${color}` }, `${level} (${risk}%)`)
          }
        },
        {
          name: 'Avg Score',
          sort: true,
          formatter: (cell) => {
            const score = parseInt(cell)
            let level = "Low", color = "bg-red-100 text-red-800"
            if (score >= 85) { level = "High"; color = "bg-green-100 text-green-800 font-bold" }
            else if (score >= 50) { level = "Med"; color = "bg-yellow-100 text-yellow-800" }
            return h('span', { className: `inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium ${color}` }, `${level} (${score}%)`)
          }
        },
        {
          name: 'Last Active',
          sort: false,
          formatter: (cell) => cell === null ? 'Never' : `${cell} days ago`
        },
        {
          name: 'Actions',
          sort: false,
          formatter: (cell, row) => {
            return h('a', {
              href: `/dashboard/students/${row.cells[7].data}`,
              className: 'text-indigo-600 hover:text-indigo-900 text-sm font-medium'
            }, 'View')
          }
        },
        { name: 'id', hidden: true, sort: false }
      ],
      autoWidth: true,
      data: students.map(s => [
        s.rank,
        s.name,
        s.email,
        s.risk_percent,
        s.engagement,
        s.last_active_days_ago,
        null,
        s.id
      ]),
      search: true,
      sort: true,
      pagination: { limit: 10 },
      className: {
        table: 'min-w-full divide-y divide-gray-200',
        th: 'px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider bg-gray-50',
        td: 'px-6 py-4 text-sm text-gray-900'
      }
    }).render(this.gridContainerTarget)
  }
}
