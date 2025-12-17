import { application } from "controllers/application"
// Обратите внимание: импортируем lazyLoad...
import { lazyLoadControllersFrom } from "@hotwired/stimulus-loading"

// Меняем eager на lazy
lazyLoadControllersFrom("controllers", application)
