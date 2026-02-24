package com.block.wt.services

import com.block.wt.model.ContextConfig
import com.block.wt.util.ConfigFileHelper
import com.block.wt.util.PathHelper
import com.intellij.openapi.application.ApplicationManager
import com.intellij.openapi.components.Service
import com.intellij.openapi.components.service
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

@Service(Service.Level.APP)
class ContextService {

    private val _currentContextName = MutableStateFlow<String?>(null)
    val currentContextName: StateFlow<String?> = _currentContextName.asStateFlow()

    private val _contexts = MutableStateFlow<List<ContextConfig>>(emptyList())
    val contexts: StateFlow<List<ContextConfig>> = _contexts.asStateFlow()

    @Volatile
    private var cachedConfig: ContextConfig? = null

    fun initialize() {
        reload()
    }

    fun reload() {
        _currentContextName.value = ConfigFileHelper.readCurrentContext()
        _contexts.value = listContexts()
        cachedConfig = _currentContextName.value?.let { getConfig(it) }
    }

    fun listContexts(): List<ContextConfig> {
        return ConfigFileHelper.listConfigFiles().mapNotNull { ConfigFileHelper.readConfig(it) }
    }

    fun getCurrentConfig(): ContextConfig? {
        if (cachedConfig == null) {
            val name = _currentContextName.value ?: ConfigFileHelper.readCurrentContext() ?: return null
            cachedConfig = getConfig(name)
        }
        return cachedConfig
    }

    fun getConfig(name: String): ContextConfig? {
        val confFile = PathHelper.reposDir.resolve("$name.conf")
        return ConfigFileHelper.readConfig(confFile)
    }

    fun switchContext(name: String) {
        ConfigFileHelper.setCurrentContext(name)
        _currentContextName.value = name
        cachedConfig = getConfig(name)
    }

    fun addContext(config: ContextConfig) {
        val confFile = PathHelper.reposDir.resolve("${config.name}.conf")
        ConfigFileHelper.writeConfig(confFile, config)
        reload()
    }

    companion object {
        fun getInstance(): ContextService =
            ApplicationManager.getApplication().service()
    }
}
