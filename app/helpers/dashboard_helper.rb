module DashboardHelper
  def engagement_class(score)
      score >= 70 ? 'high' : score >= 50 ? 'medium' : 'low'
  end
end