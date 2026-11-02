"""Merchant-side shop routes, mounted at /api/v1/merchants/shop/ as in the API spec."""
from django.urls import path

from . import views

app_name = "merchant-shops"

urlpatterns = [
    path("create/", views.ShopCreateView.as_view(), name="create"),
    path("list/", views.ShopListView.as_view(), name="list"),
    path("update/<int:pk>/", views.ShopUpdateView.as_view(), name="update"),
    path("<int:pk>/documents/", views.ShopDocumentListCreateView.as_view(), name="documents"),
]
