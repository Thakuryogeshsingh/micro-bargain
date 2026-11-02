from django.urls import path

from . import views

app_name = "commissions"

urlpatterns = [
    path("", views.MerchantCommissionListView.as_view(), name="list"),
    path("summary/", views.MerchantCommissionSummaryView.as_view(), name="summary"),
]
