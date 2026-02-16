module ApplicationHelper
  def nav_link_class(path)
    base_classes = "block px-6 py-3 transition"
    active_classes = "bg-indigo-800 border-l-4 border-indigo-400"
    inactive_classes = "hover:bg-indigo-800"
    
    if current_page?(path)
      "#{base_classes} #{active_classes}"
    else
      "#{base_classes} #{inactive_classes}"
    end
  end
end
