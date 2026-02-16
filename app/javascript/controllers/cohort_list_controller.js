import { Controller } from "@hotwired/stimulus"
import dashboardCohorts from "api/Dashboard/CohortsApi"

export default class extends Controller {
  static targets = [
    "summarySkeleton",
    "summarySection",
    "thrivingSection",
    "thrivingSkeleton",
    "steadySection",
    "steadySkeleton",
    "needsSupportSection",
    "needsSupportSkeleton"
  ]

  connect() {
    this.cohorts = []
    this.load()
  }

  async load() {
    try {
      const url = dashboardCohorts.index.path({ query: { format: 'json' } })
      const response = await fetch(url)
      if (!response.ok) throw new Error('Network response was not ok')

      const data = await response.json()

      this.cohorts = data.cohorts || []

      if (data.summary) this.renderSummary(data.summary)
      if (data.cohorts) this.renderCohorts(data.cohorts)
    } catch (error) {
      console.error('Error fetching cohorts:', error)
      this.showError()
    }
  }

  renderSummary(summary) {
    // Hide skeleton and show summary
    this.summarySkeletonTarget.classList.add('hidden')
    this.summarySectionTarget.classList.remove('hidden')

    // Update KPI values
    const avgEngagementEl = this.summarySectionTarget.querySelector('[data-kpi="avg-engagement"]')
    const totalStudentsEl = this.summarySectionTarget.querySelector('[data-kpi="total-students"]')
    const totalAtRiskEl = this.summarySectionTarget.querySelector('[data-kpi="total-at-risk"]')
    const topPerformerEl = this.summarySectionTarget.querySelector('[data-kpi="top-performer"]')
    const topPerformerEngagementEl = this.summarySectionTarget.querySelector('[data-kpi="top-performer-engagement"]')

    if (avgEngagementEl) avgEngagementEl.textContent = `${summary.average_engagement_percent}%`
    if (totalStudentsEl) totalStudentsEl.textContent = summary.total_students?.toLocaleString() || '0'
    if (totalAtRiskEl) totalAtRiskEl.textContent = summary.total_at_risk?.toLocaleString() || '0'

    // Find top performing cohort
    const thrivingCohorts = this.cohorts.filter(c => c.tier === 'thriving')
    if (thrivingCohorts.length > 0 && topPerformerEl && topPerformerEngagementEl) {
      const top = thrivingCohorts[0]
      topPerformerEl.textContent = top.name
      topPerformerEngagementEl.textContent = `${top.engagement_percent}% engagement`
    }

    // Update header subtitle
    const subtitleEl = document.querySelector('[data-cohort-subtitle]')
    if (subtitleEl) {
      subtitleEl.textContent = `${summary.total_cohorts} cohorts • ${summary.total_students} students learning together`
    }
  }

  renderCohorts(cohorts) {
    const thriving = cohorts.filter(c => c.tier === 'thriving')
    const steady = cohorts.filter(c => c.tier === 'steady')
    const needsSupport = cohorts.filter(c => c.tier === 'needs_support')

    if (thriving.length > 0) {
      this.renderTierSection('thriving', thriving, this.thrivingSectionTarget, this.thrivingSkeletonTarget)
    } else {
      this.thrivingSectionTarget.classList.add('hidden')
      this.thrivingSkeletonTarget.classList.add('hidden')
    }

    if (steady.length > 0) {
      this.renderTierSection('steady', steady, this.steadySectionTarget, this.steadySkeletonTarget)
    } else {
      this.steadySectionTarget.classList.add('hidden')
      this.steadySkeletonTarget.classList.add('hidden')
    }

    if (needsSupport.length > 0) {
      this.renderTierSection('needs_support', needsSupport, this.needsSupportSectionTarget, this.needsSupportSkeletonTarget)
    } else {
      this.needsSupportSectionTarget.classList.add('hidden')
      this.needsSupportSkeletonTarget.classList.add('hidden')
    }
  }

  renderTierSection(tier, cohorts, sectionTarget, skeletonTarget) {
    skeletonTarget.classList.add('hidden')
    sectionTarget.classList.remove('hidden')

    const container = sectionTarget.querySelector('[data-cohorts-container]')
    if (!container) return

    container.innerHTML = cohorts.map(cohort => this.createCohortCard(cohort, tier)).join('')
  }

  createCohortCard(cohort, tier) {
    const tierConfig = {
      thriving: {
        borderColor: 'border-green-500',
        badgeColor: 'bg-green-500',
        threshold: '≥ 85%'
      },
      steady: {
        borderColor: 'border-yellow-500',
        badgeColor: 'bg-yellow-500',
        threshold: '50-85%'
      },
      needs_support: {
        borderColor: 'border-red-500',
        badgeColor: 'bg-red-500',
        threshold: '< 50%'
      }
    }

    const config = tierConfig[tier] || tierConfig.steady
    const atRiskColor = cohort.at_risk_count > 10 ? 'text-red-600' :
      cohort.at_risk_count > 5 ? 'text-orange-600' :
        'text-gray-600'

    return `
      <div class="bg-white rounded-lg border-l-4 ${config.borderColor} shadow-sm hover:shadow-md transition-shadow p-6">
        <div class="flex items-start justify-between mb-3">
          <div class="flex-1">
            <h4 class="text-lg font-bold text-gray-900">${this.escapeHtml(cohort.name)}</h4>
            <p class="text-sm text-gray-500">${this.escapeHtml(cohort.program)}</p>
          </div>
          <div class="${config.badgeColor} text-white rounded-full px-3 py-1 text-xs font-semibold ml-3">
            ${cohort.engagement_percent}%
          </div>
        </div>
        
        <div class="space-y-2 mb-4 pb-4 border-b border-gray-100">
          <div class="flex items-center justify-between text-sm">
            <span class="text-gray-600">Students</span>
            <span class="font-semibold text-gray-900">${cohort.student_count}</span>
          </div>
          <div class="flex items-center justify-between text-sm">
            <span class="text-gray-600">At Risk</span>
            <span class="${atRiskColor} font-medium">${cohort.at_risk_count}</span>
          </div>
          <div class="text-sm text-gray-600">
            ${this.escapeHtml(cohort.instructor_name || 'N/A')}
          </div>
        </div>
        
        <a href="/dashboard/cohorts/${cohort.id}" class="block w-full text-sm font-medium text-gray-700 hover:text-gray-900 hover:underline text-left transition-colors">
          View Cohort →
        </a>
      </div>
    `
  }


  showError() {
    // Hide all skeletons and show error message
    this.summarySkeletonTarget?.classList.add('hidden')
    this.thrivingSkeletonTarget?.classList.add('hidden')
    this.steadySkeletonTarget?.classList.add('hidden')
    this.needsSupportSkeletonTarget?.classList.add('hidden')

    const errorHtml = `
      <div class="bg-white rounded-lg shadow p-12 text-center">
        <svg class="w-16 h-16 text-red-400 mx-auto mb-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path>
        </svg>
        <h3 class="text-lg font-semibold text-gray-900 mb-2">Error Loading Cohorts</h3>
        <p class="text-gray-600">Please try again or contact support if the issue persists</p>
      </div>
    `

    this.element.insertAdjacentHTML('beforeend', errorHtml)
  }

  escapeHtml(text) {
    if (!text) return ''
    const div = document.createElement('div')
    div.textContent = text
    return div.innerHTML
  }
}
