package com.block.wt.model

import com.google.gson.annotations.SerializedName

data class ProvisionMarker(
    val current: String,
    val provisions: List<ProvisionEntry>,
)

data class ProvisionEntry(
    val context: String,
    @SerializedName("provisioned_at") val provisionedAt: String,
    @SerializedName("provisioned_by") val provisionedBy: String,
)
