from django.urls import path

from . import views

app_name = "analytics"

urlpatterns = [
    path("dashboard/", views.ReportView.as_view(kind="dashboard"), name="dashboard"),
    path("merchants/", views.ReportView.as_view(kind="merchants"), name="merchants"),
    path("customers/", views.ReportView.as_view(kind="customers"), name="customers"),
    path("deals/", views.ReportView.as_view(kind="deals"), name="deals"),
    path("merchant-sales/", views.MerchantSalesView.as_view(), name="merchant-sales"),
]
