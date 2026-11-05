from django.urls import path

from . import views

app_name = "merchants"

urlpatterns = [
    path("register/", views.MerchantRegisterView.as_view(), name="register"),
    path("profile/", views.MerchantProfileView.as_view(), name="profile"),
    path("profile/update/", views.MerchantProfileUpdateView.as_view(), name="profile-update"),
    path("dashboard/", views.MerchantDashboardView.as_view(), name="dashboard"),
    path("onboarding/", views.OnboardingView.as_view(), name="onboarding"),
]
