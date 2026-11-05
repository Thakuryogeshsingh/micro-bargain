from django.urls import path

from . import views

app_name = "quality"

urlpatterns = [
    path("complaints/", views.ComplaintListCreateView.as_view(), name="complaints"),
    path("shop-complaints/", views.ShopComplaintsView.as_view(), name="shop-complaints"),
    path("complaints/<int:pk>/respond/", views.RespondView.as_view(), name="respond"),
]
