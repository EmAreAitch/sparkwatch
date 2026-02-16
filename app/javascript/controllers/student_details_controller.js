import { Controller } from "@hotwired/stimulus"
import { Chart, registerables } from "chart.js"
import dashboardStudent from "api/Dashboard/StudentsApi"

Chart.register(...registerables)

export default class extends Controller {
  static targets = [
    "info", "infoSkeleton",
    "cohort", "instructor", "program",
    "kpi", "kpiSkeleton", "engagement", "engagementKpi", "engagementKpiSkeleton",
    "engagementTrend", "risk", "riskLevel", "riskTrendLabel",
    "attendance", "attendanceKpi", "attendanceKpiSkeleton",
    "lastActive", "lastactiveKpi", "lastactiveKpiSkeleton",
    "engagementBreakdown", "engagementBreakdownSkeleton",
    "engagementChart", "engagementChartSkeleton",
    "riskChart", "riskChartSkeleton",
    "activities", "activitiesSkeleton", "activitiesEmpty",
    "recommendations", "recommendationsSkeleton", "recommendationsEmpty",
    "riskFactors", "riskFactorsSkeleton",
    "engagementAnalysis", "engagementAnalysisSkeleton"
  ]

  static values = { studentId: String }
  charts = []

  connect() {
    this.load()
  }

  disconnect() {
    this.charts.forEach(c => c?.destroy())
  }

  async load() {
    const widgets = [
      "student_info",
      "kpis",
      "engagement_breakdown",
      "engagement_trend",
      "risk_trend",
      "recent_activities",
      "recommendations",
      "risk_factors",
      "engagement_analysis"
    ]

    const url = dashboardStudent.show.path({
      id: this.studentIdValue,
      query: { widgets }
    })

    const res = await fetch(url)

    const data = await res.json()

    if (data.student_info) this.renderInfo(data.student_info)
    if (data.kpis) this.renderKPIs(data.kpis)
    if (data.engagement_breakdown) this.renderEngagementBreakdown(data.engagement_breakdown)
    if (data.engagement_trend) this.renderEngagementChart(data.engagement_trend)
    if (data.risk_trend) this.renderRiskChart(data.risk_trend)
    if (data.recent_activities) this.renderActivities(data.recent_activities)
    if (data.recommendations) this.renderRecommendations(data.recommendations)
    if (data.risk_factors) this.renderRiskFactors(data.risk_factors)
    if (data.engagement_analysis) this.renderEngagementAnalysis(data.engagement_analysis)
  }

  renderInfo(info) {
    document.querySelector("#studentName").textContent = info.name
    const emailEl = document.querySelector("#studentEmailSubtitle")
    if (emailEl) emailEl.textContent = info.email

    this.cohortTarget.textContent = info.cohort_name || "—"
    this.instructorTarget.textContent = info.instructor_name || "—"
    this.programTarget.textContent = info.program || "—"

    this.infoSkeletonTarget.classList.add("hidden")
    this.infoTarget.classList.remove("hidden")
  }

  renderKPIs(kpis) {
    // Risk (Hero metric)
    const riskPercent = kpis.risk_score_percent
    this.riskTarget.textContent = `${riskPercent}%`
    this.riskTarget.className = `text-4xl font-bold ${this.riskColor(riskPercent)}`

    if (kpis.risk_level) {
      const riskLevel = kpis.risk_level
      this.riskLevelTarget.textContent = this.riskLevelBadge(riskLevel)
      this.riskLevelTarget.className = `text-sm font-semibold ${this.riskLevelColor(riskLevel)}`
    }

    // Risk trend
    if (kpis.risk_trend) {
      const trend = kpis.risk_trend
      const trendArrow = trend === 'improving' ? '↗️ Improving' : trend === 'declining' ? '↘️ Declining' : '→ Stable'
      this.riskTrendLabelTarget.textContent = trendArrow
    }

    // Engagement with trend
    const engagementPercent = kpis.current_engagement_percent
    this.engagementTarget.textContent = `${engagementPercent}%`
    this.engagementTarget.className = `text-3xl font-bold ${this.engagementColor(engagementPercent)}`

    if (kpis.engagement_trend) {
      const trend = kpis.engagement_trend
      const delta = kpis.engagement_trend_delta
      const sign = delta > 0 ? '+' : ''
      const deltaLabel = (delta === null || delta === undefined) ? '' : ` (${sign}${delta}%)`
      const trendLabel = trend === 'improving' ? `↗️ Improving${deltaLabel}` : trend === 'declining' ? `↘️ Declining${deltaLabel}` : `→ Stable${deltaLabel}`
      this.engagementTrendTarget.textContent = trendLabel
    }

    // Attendance
    const attendancePercent = kpis.attendance_rate_percent
    this.attendanceTarget.textContent = `${attendancePercent}%`
    this.attendanceTarget.className = `text-3xl font-bold ${this.attendanceColor(attendancePercent)}`

    // Last Active
    this.lastActiveTarget.textContent =
      kpis.last_active_days_ago !== null ? `${kpis.last_active_days_ago}d` : "Never"

    // Hide skeletons, show data
    this.kpiSkeletonTarget.classList.add("hidden")
    this.kpiTarget.classList.remove("hidden")
    this.engagementKpiSkeletonTarget.classList.add("hidden")
    this.engagementKpiTarget.classList.remove("hidden")
    this.attendanceKpiSkeletonTarget.classList.add("hidden")
    this.attendanceKpiTarget.classList.remove("hidden")
    this.lastactiveKpiSkeletonTarget.classList.add("hidden")
    this.lastactiveKpiTarget.classList.remove("hidden")
    // Update explanatory heading based on risk level
    if (this.hasRiskHeadingTarget) {
      const level = kpis.risk_level || (riskPercent >= 70 ? 'high' : riskPercent >= 40 ? 'medium' : 'low')
      if (level === 'high') {
        this.riskHeadingTarget.textContent = `Why predicted risk: HIGH`;
        this.riskHeadingTarget.className = 'text-xl font-bold text-red-700 mb-6'
      } else if (level === 'medium') {
        this.riskHeadingTarget.textContent = `Why predicted risk: ELEVATED`;
        this.riskHeadingTarget.className = 'text-xl font-bold text-yellow-700 mb-6'
      } else {
        this.riskHeadingTarget.textContent = `Why this prediction`;
        this.riskHeadingTarget.className = 'text-xl font-bold text-gray-900 mb-6'
      }
    }
  }

  renderRiskFactors(factors) {
    if (!this.hasRiskFactorsTarget) return

    if (!factors || factors.length === 0) {
      this.riskFactorsTarget.innerHTML = `<p class="text-gray-500 text-sm">No significant risk factors identified</p>`
    } else {
      this.riskFactorsTarget.innerHTML = factors.map(factor => {
        const severityColor = factor.severity === 'critical'
          ? 'border-red-300 bg-red-50'
          : factor.severity === 'warning' ? 'border-yellow-300 bg-yellow-50' : 'border-green-200 bg-green-50'
        const severityBadgeColor = factor.severity === 'critical'
          ? 'bg-red-100 text-red-800'
          : factor.severity === 'warning' ? 'bg-yellow-100 text-yellow-800' : 'bg-green-100 text-green-800'

        return `
          <div class="border ${severityColor} rounded-lg p-4">
            <div class="flex items-start justify-between">
              <div>
                <p class="font-semibold text-gray-900">#${factor.rank} ${factor.factor}</p>
                <p class="text-sm text-gray-700 mt-1">${factor.description}</p>
              </div>
              <span class="text-xs font-semibold px-2 py-1 rounded ${severityBadgeColor}">
                ${factor.severity.toUpperCase()}
              </span>
            </div>
          </div>
        `
      }).join("")
    }

    if (this.hasRiskFactorsSkeletonTarget) this.riskFactorsSkeletonTarget.classList.add("hidden")
    this.riskFactorsTarget.classList.remove("hidden")
  }

  renderEngagementAnalysis(analysis) {
    if (!this.hasEngagementAnalysisTarget) return

    const { current_breakdown, lowest_component, highest_component, cohort_average, vs_cohort, trend, components, trend_delta } = analysis

    const vsLabel = vs_cohort > 0 ? `+${vs_cohort}%` : `${vs_cohort}%`
    const vsColor = vs_cohort > 0 ? 'text-green-600' : 'text-red-600'

    // humanize keys like "parent" -> "Parent Engagement"
    const humanize = s => String(s).replace(/_/g, ' ').replace(/\b\w/g, c => c.toUpperCase())

    this.engagementAnalysisTarget.innerHTML = `
      <div class="grid grid-cols-2 gap-4 mb-4 pb-4 border-b border-gray-200">
        <div>
          <p class="text-xs text-gray-500">Cohort Average</p>
          <p class="text-lg font-semibold text-gray-900 mt-1">${cohort_average}%</p>
        </div>
        <div>
          <p class="text-xs text-gray-500">vs Cohort</p>
          <p class="text-lg font-semibold ${vsColor} mt-1">${vsLabel}</p>
        </div>
      </div>

      <div class="mb-4 pb-4 border-b border-gray-200">
        <p class="text-xs text-gray-500 font-semibold uppercase mb-2">Trend</p>
        <p class="text-sm text-gray-700">
          ${(() => {
        const sign = trend_delta > 0 ? '+' : ''
        const deltaLabel = (trend_delta === null || trend_delta === undefined) ? '' : ` (${sign}${trend_delta}%)`
        return trend === 'improving' ? `↗️ <strong>Improving</strong> - Great momentum!${deltaLabel}` :
          trend === 'declining' ? `↘️ <strong>Declining</strong> - Needs attention${deltaLabel}` :
            `→ <strong>Stable</strong> - Consistent performance${deltaLabel}`
      })()}
        </p>
      </div>

      <div>
        <p class="text-xs text-gray-500 font-semibold uppercase mb-3">Summary</p>
        <p class="text-sm text-gray-700 mb-1">Highest: ${humanize(highest_component[0])} ${highest_component[1]}%</p>
        <p class="text-sm text-gray-700">Lowest: ${humanize(lowest_component[0])} ${lowest_component[1]}%</p>
      </div>
    `

    if (this.hasEngagementAnalysisSkeletonTarget) this.engagementAnalysisSkeletonTarget.classList.add("hidden")
    this.engagementAnalysisTarget.classList.remove("hidden")
  }

  engagementColor(value) {
    if (value >= 70) return "text-green-600"
    if (value >= 50) return "text-yellow-600"
    return "text-red-600"
  }

  riskColor(value) {
    if (value >= 70) return "text-red-600"
    if (value >= 40) return "text-yellow-600"
    return "text-green-600"
  }

  attendanceColor(value) {
    if (value >= 80) return "text-green-600"
    if (value >= 60) return "text-yellow-600"
    return "text-red-600"
  }

  riskLevelBadge(level) {
    const labels = { high: "HIGH RISK", medium: "MEDIUM RISK", low: "LOW RISK" }
    return labels[level] || level.toUpperCase()
  }

  riskLevelColor(level) {
    if (level === "high") return "text-red-600"
    if (level === "medium") return "text-yellow-600"
    return "text-green-600"
  }

  breakdownColor(value) {
    if (value < 40) return "bg-red-500"
    if (value < 70) return "bg-orange-400"
    return "bg-green-500"
  }

  renderEngagementBreakdown(breakdown) {
    const labels = {
      attendance: "Attendance",
      assignments: "Assignments",
      quizzes: "Quizzes",
      questions: "Questions",
      parent: "Parent Engagement"
    }

    const entries = Object.keys(labels).map(key => ({
      key,
      value: breakdown[key] ?? 0,
      label: labels[key]
    }))
    const lowest = entries.reduce((min, curr) => curr.value < min.value ? curr : min, entries[0])

    if (!this.hasEngagementBreakdownTarget) return

    this.engagementBreakdownTarget.innerHTML = entries.map(item => {
      const isLowest = item.key === lowest.key && item.value < 70
      return `
        <div>
          <div class="flex justify-between text-sm mb-1">
            <span class="text-gray-600 flex items-center gap-1">
              ${item.label}
              ${isLowest ? '<span class="text-red-500">⚠️</span>' : ''}
            </span>
            <span class="font-semibold text-gray-900">${item.value}%</span>
          </div>
          <div class="w-full h-2 bg-gray-200 rounded">
            <div class="h-2 rounded ${this.breakdownColor(item.value)}"
                 style="width:${item.value}%"></div>
          </div>
        </div>
      `
    }).join("")
    if (this.hasEngagementBreakdownSkeletonTarget) this.engagementBreakdownSkeletonTarget.classList.add("hidden")
    this.engagementBreakdownTarget.classList.remove("hidden")
  }

  renderEngagementChart(trend) {
    if (!this.hasEngagementChartTarget) return

    this.charts.push(new Chart(this.engagementChartTarget, {
      type: "line",
      data: {
        labels: trend.map(t => t.week_label),
        datasets: [
          {
            label: "Student",
            data: trend.map(t => t.engagement_percent),
            borderColor: "rgb(34, 197, 94)",
            backgroundColor: "rgba(34, 197, 94, 0.15)",
            fill: true,
            tension: 0.4
          },
          {
            label: "Cohort Avg",
            data: trend.map(t => t.cohort_engagement_percent),
            borderColor: "rgb(107, 114, 128)",
            backgroundColor: "rgba(107, 114, 128, 0.1)",
            borderDash: [6, 4],
            fill: false,
            tension: 0.4
          }
        ]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
          legend: { display: true }
        },
        scales: {
          y: { beginAtZero: true, max: 100 }
        }
      }
    }))

    if (this.hasEngagementChartSkeletonTarget) this.engagementChartSkeletonTarget.classList.add("hidden")
    this.engagementChartTarget.classList.remove("hidden")
  }

  renderRiskChart(trend) {
    if (!this.hasRiskChartTarget) return

    this.charts.push(new Chart(this.riskChartTarget, {
      type: "line",
      data: {
        labels: trend.map(t => t.month_label),
        datasets: [
          {
            label: "Student",
            data: trend.map(t => t.risk_percent),
            borderColor: "rgb(239, 68, 68)",
            backgroundColor: "rgba(239, 68, 68, 0.1)",
            fill: true,
            tension: 0.4
          },
          {
            label: "Cohort Avg",
            data: trend.map(t => t.cohort_risk_percent || 0),
            borderColor: "rgb(107, 114, 128)",
            backgroundColor: "rgba(107, 114, 128, 0.1)",
            borderDash: [6, 4],
            fill: false,
            tension: 0.4
          }
        ]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: { legend: { display: true } },
        scales: {
          y: {
            beginAtZero: true,
            max: 100,
            ticks: {
              callback: function (value) {
                return value + '%'
              }
            }
          }
        }
      }
    }))

    if (this.hasRiskChartSkeletonTarget) this.riskChartSkeletonTarget.classList.add("hidden")
    this.riskChartTarget.classList.remove("hidden")
  }

  renderActivities(activities) {
    if (!this.hasActivitiesTarget) return

    if (!activities || activities.length === 0) {
      if (this.hasActivitiesEmptyTarget) this.activitiesEmptyTarget.classList.remove("hidden")
      if (this.hasActivitiesSkeletonTarget) this.activitiesSkeletonTarget.classList.add("hidden")
      return
    }

    const activityIcons = {
      class_attended: { bg: "bg-blue-100", icon: "text-blue-600", emoji: "📚" },
      assignment_submitted: { bg: "bg-green-100", icon: "text-green-600", emoji: "📝" },
      quiz_taken: { bg: "bg-purple-100", icon: "text-purple-600", emoji: "📊" },
      question_asked: { bg: "bg-indigo-100", icon: "text-indigo-600", emoji: "❓" },
      parent_login: { bg: "bg-orange-100", icon: "text-orange-600", emoji: "👨‍👩‍👧‍👦" }
    }

    this.activitiesTarget.innerHTML = activities.slice(0, 10).map(activity => {
      const icon = activityIcons[activity.activity_type] || activityIcons.assignment_submitted
      return `
        <div class="flex items-start p-3 border border-gray-200 rounded-lg hover:bg-gray-50">
          <div class="${icon.bg} rounded-full p-2 mr-3 w-10 h-10 flex items-center justify-center flex-shrink-0">
            <span class="text-lg">${icon.emoji}</span>
          </div>
          <div class="flex-1">
            <p class="text-sm font-medium text-gray-900">${activity.activity_type_label}</p>
            <p class="text-xs text-gray-500 mt-0.5">${activity.days_ago} days ago</p>
          </div>
        </div>
      `
    }).join("")

    if (this.hasActivitiesSkeletonTarget) this.activitiesSkeletonTarget.classList.add("hidden")
    this.activitiesTarget.classList.remove("hidden")
  }

  renderRecommendations(recommendations) {
    if (!this.hasRecommendationsTarget) return

    if (!recommendations || recommendations.length === 0) {
      if (this.hasRecommendationsEmptyTarget) this.recommendationsEmptyTarget.classList.remove("hidden")
      if (this.hasRecommendationsSkeletonTarget) this.recommendationsSkeletonTarget.classList.add("hidden")
      return
    }

    const priorityColors = {
      1: 'text-red-700 font-bold border-l-4 border-red-600',
      2: 'text-red-600 font-semibold border-l-4 border-red-500',
      3: 'text-orange-600 font-semibold border-l-4 border-orange-500',
      4: 'text-yellow-600 border-l-4 border-yellow-500',
      default: 'text-blue-600 border-l-4 border-blue-400'
    }

    const priorityIcons = {
      1: '🚨',
      2: '⚠️',
      3: '📌',
      default: '•'
    }

    this.recommendationsTarget.innerHTML = recommendations.map(r => {
      const colorClass = priorityColors[r.priority] || priorityColors.default
      const icon = priorityIcons[r.priority] || priorityIcons.default
      return `<li class="${colorClass} pl-3 py-2 text-sm">${icon} ${r.action}</li>`
    }).join("")

    if (this.hasRecommendationsSkeletonTarget) this.recommendationsSkeletonTarget.classList.add("hidden")
    this.recommendationsTarget.classList.remove("hidden")
  }
}
