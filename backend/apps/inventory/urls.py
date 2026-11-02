from django.urls import path

from . import views

app_name = "inventory"

urlpatterns = [
    path("", views.InventoryListView.as_view(), name="list"),
    path("adjust/", views.InventoryAdjustView.as_view(), name="adjust"),
    path("<int:pk>/movements/", views.MovementListView.as_view(), name="movements"),
]
