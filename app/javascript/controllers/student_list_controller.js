import { Controller } from "@hotwired/stimulus"
import dashboardStudent from "api/Dashboard/StudentsApi"

export default class extends Controller {
  static targets = [
    "searchInput",
    "cohortFilter",
    "riskFilter",
    "engagementFilter",
    "orderFilter",
    "emptyState",
    "resultsSection",
    "resultsBody",
    "loadingState",
    "paginationControls",
    "prevBtn",
    "nextBtn",
    "pageNumber"
  ]

  connect() {
    this.pages = []
    this.currentPageIndex = 0
    this.nextPageUrl = null
  }

  handleKeypress(event) {
    if (event.key === 'Enter') {
      this.search()
    }
  }

  handleOrderChange() {
    this.search()
  }

  search() {
    this.resetPagination()
    this.fetchPage()
  }

  async fetchPage() {
    const url = this.nextPageUrl || this.buildInitialUrl()

    this.showLoading()

    try {
      const response = await fetch(url)
      if (!response.ok) throw new Error('Network response was not ok')

      const data = await response.json()

      this.pages.push(data.data)
      this.nextPageUrl = data.pagy

      this.renderCurrentPage()
      this.updatePaginationControls()
      this.showResults()
    } catch (error) {
      console.error('Error fetching students:', error)
      this.showError()
    }
  }

  nextPage() {
    const nextIndex = this.currentPageIndex + 1

    if (this.pages[nextIndex]) {
      // Page already cached
      this.currentPageIndex = nextIndex
      this.renderCurrentPage()
      this.updatePaginationControls()
    } else if (this.nextPageUrl) {
      // Need to fetch next page
      this.currentPageIndex = nextIndex
      this.fetchPage()
    }
  }

  prevPage() {
    if (this.currentPageIndex > 0) {
      this.currentPageIndex--
      this.renderCurrentPage()
      this.updatePaginationControls()
    }
  }

  renderCurrentPage() {
    const students = this.pages[this.currentPageIndex] || []

    this.resultsBodyTarget.innerHTML = students.map(student =>
      this.createStudentRow(student)
    ).join('')
  }

  createStudentRow(student) {
    const riskLevel = this.getRiskLevel(student.risk_score)
    const riskColor = this.getRiskColor(riskLevel)

    const engagementLevel = this.getEngagementLevel(student.engagement)
    const engagementColor = this.getEngagementColor(engagementLevel)

    return `
      <tr class="hover:bg-gray-50">
        <td class="px-4 sm:px-6 py-4">
          <div class="font-medium text-gray-900">${this.escapeHtml(student.name)}</div>
          <div class="text-sm text-gray-500">${this.escapeHtml(student.email)}</div>
        </td>
        <td class="px-4 sm:px-6 py-4 text-sm text-gray-600">${this.escapeHtml(student.cohort)}</td>
        <td class="px-4 sm:px-6 py-4 whitespace-nowrap">
          <span class="inline-block px-2 py-1 text-xs rounded-full ${engagementColor} font-medium">
            ${engagementLevel} (${student.engagement}%)
          </span>
        </td>
        <td class="px-4 sm:px-6 py-4 whitespace-nowrap">
          <span class="inline-block px-2 py-1 text-xs rounded-full ${riskColor} font-medium">
            ${riskLevel} (${student.risk_score}%)
          </span>
        </td>
        <td class="px-4 sm:px-6 py-4 text-sm text-gray-600 hidden sm:table-cell">${student.last_active}</td>
        <td class="px-4 sm:px-6 py-4">
          <a href="/dashboard/students/${student.id}" class="text-indigo-600 hover:text-indigo-900 text-sm font-medium">
            View
          </a>
        </td>
      </tr>
    `
  }

  updatePaginationControls() {
    this.pageNumberTarget.textContent = this.currentPageIndex + 1

    // Previous button
    this.prevBtnTarget.disabled = this.currentPageIndex === 0

    // Next button
    const hasNextCached = !!this.pages[this.currentPageIndex + 1]
    const canFetchNext = !!this.nextPageUrl
    this.nextBtnTarget.disabled = !hasNextCached && !canFetchNext
  }

  buildInitialUrl() {
    const query = {
      search: this.searchInputTarget.value.trim(),
      cohort: this.cohortFilterTarget.value,
      risk_level: this.riskFilterTarget.value,
      engagement_level: this.engagementFilterTarget.value,
      order: this.orderFilterTarget.value
    }

    return dashboardStudent.index.path({ query })
  }

  resetPagination() {
    this.pages = []
    this.currentPageIndex = 0
    this.nextPageUrl = null
    this.resultsBodyTarget.innerHTML = ''
  }

  clearFilters() {
    this.searchInputTarget.value = ''
    this.cohortFilterTarget.value = ''
    this.riskFilterTarget.value = ''
    this.engagementFilterTarget.value = ''
    this.orderFilterTarget.value = ''

    this.resetPagination()
    this.showEmptyState()
  }

  showLoading() {
    this.emptyStateTarget.classList.add('hidden')
    this.resultsSectionTarget.classList.remove('hidden')
    this.resultsBodyTarget.innerHTML = ''
    this.loadingStateTarget.classList.remove('hidden')
    this.paginationControlsTarget.classList.add('hidden')
  }

  showResults() {
    this.loadingStateTarget.classList.add('hidden')
    this.emptyStateTarget.classList.add('hidden')
    this.resultsSectionTarget.classList.remove('hidden')
    this.paginationControlsTarget.classList.remove('hidden')
  }

  showEmptyState() {
    this.resultsSectionTarget.classList.add('hidden')
    this.emptyStateTarget.classList.remove('hidden')
    this.emptyStateTarget.innerHTML = `
      <svg class="w-16 h-16 text-gray-400 mx-auto mb-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"></path>
      </svg>
      <h3 class="text-lg font-semibold text-gray-900 mb-2">Search for Students</h3>
      <p class="text-gray-600">Enter a name, email, or apply filters to find students</p>
    `
  }

  showError() {
    this.loadingStateTarget.classList.add('hidden')
    this.emptyStateTarget.classList.remove('hidden')
    this.emptyStateTarget.innerHTML = `
      <svg class="w-16 h-16 text-red-400 mx-auto mb-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path>
      </svg>
      <h3 class="text-lg font-semibold text-gray-900 mb-2">Error Loading Students</h3>
      <p class="text-gray-600">Please try again or contact support if the issue persists</p>
    `
  }

  getRiskLevel(score) {
    if (score >= 90) return 'High'
    if (score >= 75) return 'Medium'
    return 'Low'
  }

  getRiskColor(level) {
    const colors = {
      'High': 'bg-red-100 text-red-800',
      'Medium': 'bg-orange-100 text-orange-800',
      'Low': 'bg-green-100 text-green-800'
    }
    return colors[level]
  }

  getEngagementLevel(score) {
    if (score >= 85) return 'High'
    if (score >= 50) return 'Medium'
    return 'Low'
  }

  getEngagementColor(level) {
    const colors = {
      'High': 'bg-green-100 text-green-800',
      'Medium': 'bg-orange-100 text-orange-800',
      'Low': 'bg-red-100 text-red-800'
    }
    return colors[level]
  }

  escapeHtml(text) {
    const div = document.createElement('div')
    div.textContent = text
    return div.innerHTML
  }
}
