from django.urls import path

from . import views

app_name = "customers"

urlpatterns = [
    path("profile/", views.CustomerProfileView.as_view(), name="profile"),
    path("addresses/", views.AddressListCreateView.as_view(), name="address-list"),
    path("addresses/<int:pk>/", views.AddressDetailView.as_view(), name="address-detail"),
    path("referral/", views.ReferralView.as_view(), name="referral"),
    path("impact/", views.ImpactView.as_view(), name="impact"),
    path("wallet/", views.WalletView.as_view(), name="wallet"),
    path("plus/", views.PlusView.as_view(), name="plus"),
]
