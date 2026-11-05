from django.urls import path

from . import views

app_name = "daily"

urlpatterns = [
    path("", views.MyDailyView.as_view(), name="mine"),
    path("products/", views.ShopProductsView.as_view(), name="products"),
    path("<int:pk>/status/", views.DailyStatusView.as_view(), name="status"),
    path("shop/", views.ShopDayView.as_view(), name="shop-day"),
    path("shop/<int:pk>/deliver/", views.DeliverView.as_view(), name="deliver"),
]
